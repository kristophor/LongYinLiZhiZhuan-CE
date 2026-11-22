function E.saveDiscipleAll(previous,selected,inputs)
 check(not E.busy,'已有操作执行中')
 local fresh=E.discipleSnapshot()
 check(same(previous.context,fresh.context) and previous.force==fresh.force and previous.id==fresh.id,'已读档或切换门派，请重新打开编辑窗口')
 local r;for _,row in ipairs(fresh.rows)do if row.id==selected.id and row.ptr==selected.ptr then r=row;break end end
 check(r and not r.dead,'该弟子已离开、失效或死亡')
 local changes={};local seen={}
 -- Validate every requested field before the first write.
 for _,input in ipairs(inputs)do
  local key,g,m=input.key,input.group,input.mode;local token=key..':'..g..':'..m
  check(not seen[token],'重复属性');seen[token]=true
  local spec=E.discipleEditSpec(r,key,g,m);local v=tonumber(input.value)
  local limit=spec.maxKey and r[spec.maxKey] or spec.max
  check(v and v==v and v>=spec.min and v<=limit and (not spec.integer or v%1==0),spec.label..'：请输入 '..spec.min..'～'..limit..(spec.integer and ' 的整数' or ' 的数值'))
  local before=E.discipleValue(selected,key,g,m);local now=E.discipleValue(r,key,g,m)
  check(equal(before,now),spec.label..' 已变化，请重新读取后修改')
  if not equal(v,now)then changes[#changes+1]={key=key,group=g,mode=m,value=v}end
 end
 if #changes==0 then return '没有修改任何数值。'end
 table.sort(changes,function(a,b)
  local x=a.group>0 and (a.mode==3 and 0 or 1) or 2
  local y=b.group>0 and (b.mode==3 and 0 or 1) or 2
  if x~=y then return x<y end;if a.group~=b.group then return a.group<b.group end;return a.key<b.key
 end)
 local history={};local prior=E.discipleUndo
 for _,v in ipairs(changes)do
  local last=E.discipleUndo
  local ok,msg=pcall(E.editDisciple,fresh,r,v.key,v.group,v.mode,v.value)
  if E.discipleUndo~=last and E.discipleUndo then history[#history+1]=E.discipleUndo end
  if not ok then E.discipleUndo=#history>0 and {batch=history} or prior;error('已保存 '..#history..' 项后停止：'..tostring(msg)..'。已完成项目可撤销。')end
 end
 E.discipleUndo={batch=history}
 return r.name..'：已保存 '..#history..' 项修改，可撤销本次保存。'
end
function E.showDiscipleAll(previous,selected)
 check(selected and not selected.dead,'请选择一名在世弟子')
 local f=createForm(false);E.discipleAllForms=E.discipleAllForms or {};E.discipleAllForms[#E.discipleAllForms+1]=f
 f.Caption='弟子全部属性 · '..selected.name..'（ID '..selected.id..'）';f.Width=1120;f.Height=745;f.Position='poScreenCenter';f.OnClose=function()return caHide or 1 end
 local function label(s,x,y,w)local p=createLabel(f);p.Caption=s;p.Left=x;p.Top=y;if w then p.Width=w end;return p end
 local header=label('',16,12,1080)
 label('基础值、属性上限可编辑；当前汇总由装备、天赋、门派等加成计算，仅作对照。',16,40,1080)
 local controls={};local snap,row=previous,selected
 local function edit(key,g,m,x,y,w)
  local p=createEdit(f);p.Left=x;p.Top=y;p.Width=w
  controls[#controls+1]={key=key,group=g,mode=m,edit=p};return p
 end
 local totals={}
 for g,spec in ipairs(E.discipleStatGroups)do
  local x=16+(g-1)*363;label(spec.name,x,76,330)
  label('属性',x,105);label('基础值',x+83,105);label('上限',x+166,105);label('当前汇总',x+253,105)
  for n,name in ipairs(spec.labels)do
   local y=133+(n-1)*30;label(name,x,y+4,80)
   edit('stat'..n,g,2,x+80,y,77);edit('stat'..n,g,3,x+163,y,77)
   totals[#totals+1]={group=g,index=n,label=label('',x+253,y+4,92)}
  end
 end
 label('人物与资源',16,422)
 local overview={{'age','年龄'},{'favor','好感'},{'loyal','忠诚'},{'contribution','功绩'},{'hp','当前生命'},{'mana','当前内力'},{'power','当前体力'},{'month','本月贡献'}}
 for n,spec in ipairs(overview)do
  local x=16+((n-1)%4)*272;local y=453+math.floor((n-1)/4)*40
  label(spec[2],x,y+4,92);edit(spec[1],0,1,x+95,y,155)
 end
 local note=label('',16,538,1080);note.WordWrap=true;note.Height=48
 local status=label('',16,636,1080);status.WordWrap=true;status.Height=60
 local function populate()
  header.Caption=row.name..' · ID '..row.id..' · '..row.role..' · '..snap.name..'（仅修改此人）'
  for _,v in ipairs(controls)do
   local enabled=not (v.key=='favor' and row.id==0)
   v.edit.Enabled=enabled
   v.edit.Text=enabled and string.format('%.9g',E.discipleValue(row,v.key,v.group,v.mode)) or '不适用'
   v.original=v.edit.Text
  end
  for _,v in ipairs(totals)do v.label.Caption=string.format('%.6g',row.stats[v.group][1][v.index])end
  note.Caption=string.format('当前上限：生命 %.6g、内力 %.6g、体力 %.6g。战力、身份和最终汇总不在这里直接写入。\n只保存改动过的输入框；基础值/上限与原单项编辑使用相同规则。',row.maxhp,row.maxmana,row.maxpower)
 end
 local function reload()
  local fresh=E.discipleSnapshot();check(same(snap.context,fresh.context) and snap.force==fresh.force,'已切换存档或门派，请关闭后重新选择弟子')
  local found;for _,r in ipairs(fresh.rows)do if r.id==row.id and r.ptr==row.ptr then found=r;break end end
  check(found and not found.dead,'弟子已离开门派或失效');snap=fresh;row=found;populate()
 end
 local function button(text,x,w,fn)
  local p=createButton(f);p.Caption=text;p.Left=x;p.Top=590;p.Width=w
  p.OnClick=function()local ok,msg=pcall(fn);status.Caption=tostring(msg);if not ok then showMessage(tostring(msg))end end
 end
 button('保存全部改动',16,230,function()
  local changes={};for _,v in ipairs(controls)do if v.edit.Enabled and v.edit.Text~=v.original then changes[#changes+1]={key=v.key,group=v.group,mode=v.mode,value=v.edit.Text}end end
  local msg=E.saveDiscipleAll(snap,row,changes);reload();if E.refreshDisciples then E.refreshDisciples()end;return msg
 end)
 button('撤销本次保存',268,230,function()
  local u=check(E.discipleUndo,'没有可撤销记录');local records=u.batch or {u}
  for _,v in ipairs(records)do check(v.row.id==row.id and v.row.ptr==row.ptr,'最近一次修改属于其他弟子，请在列表中撤销')end
  local msg=E.undoDiscipleEdit();reload();if E.refreshDisciples then E.refreshDisciples()end;return msg
 end)
 button('重新读取（放弃未保存输入）',520,300,function()reload();return '已重新读取当前弟子数据。'end)
 populate();status.Caption='可以同时修改多个输入框，再点“保存全部改动”。';f.show()
end
