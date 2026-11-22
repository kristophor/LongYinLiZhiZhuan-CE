-- Native force bonus catalog; no global configuration edits or polling writes.
function E.sectBonusSnapshot()
 local c=context();local fid=int(c.hero+0x84);check(fid>=0,'主角尚未加入门派')
 local ls=q(c.world+0x48);local a=q(ls+16);local count=int(ls+24);check(count>=0 and count<10000,'门派列表异常')
 local force
 for j=0,count-1 do local p=q(a+32+j*8);if int(p+16)==fid then force=p;break end end
 check(force and cname(force)=='ForceData','未找到当前门派')
 local bonus=q(force+0x148);check(cname(bonus)=='ForceSpeAddData','门派加成类型不符')
 local dict=q(bonus+16);local ec=int(dict+32);check(ec>=0 and ec<1000,'门派加成数量异常')
 local entries=readQword(dict+24);local values={}
 if ec>0 then check(entries and entries~=0,'加成字典不可读')end
 for j=0,ec-1 do local e=entries+32+j*16;local h=int(e);if h>=0 and h<0x80000000 then values[int(e+8)]=flt(e+12)end end
 local base=getAddressSafe('GameAssembly.dll');local manager=q(q(q(base+0x1E528F8)+0xB8)+32)
 local catalog=q(manager+0x98);local ca=q(catalog+16);local n=int(catalog+24);check(n==65,'门派加成目录已变化，请检查游戏版本')
 local rows,byID={},{}
 for id=0,n-1 do
  local p=q(ca+32+id*8);local group
  if id<=2 or id==59 then group='容量 / 上限'
  elseif id>=35 and id<=58 then group='全员属性'
  elseif id>=60 then group='领地'
  elseif id==3 or id==6 or id==7 or (id>=16 and id<=34)then group='经验 / 功绩'
  elseif id==14 or id==15 then group='资源产量'
  else group='速度 / 恢复'end
  local row={id=id,name=str(readQword(p+16)),description=str(readQword(p+24)),percent=readBytes(p+32,1)==1,value=values[id] or 0,group=group}
  rows[#rows+1]=row;byID[id]=row
 end
 check(same(c,context()) and int(c.hero+0x84)==fid,'读档或门派发生变化，请刷新')
 return {context=c,id=fid,force=force,bonus=bonus,rows=rows,byID=byID,name=str(readQword(force+0x198))~='' and str(readQword(force+0x198)) or str(readQword(force+24))}
end
function E.sectBonusCompatible(a,b)
 return a and b and same(a.context,b.context) and a.id==b.id and a.force==b.force
end
function E.setSectBonuses(previous,changes,undoing)
 check(not E.busy and not E.skillTraining,'其他操作尚未完成')
 local fresh=E.sectBonusSnapshot();check(E.sectBonusCompatible(previous,fresh),'已读档或切换门派，请刷新')
 local work={}
 if E.sectSpeedLock then for id,v in pairs(changes)do check(not E.sectSpeedTargets[id] or math.abs(v-E.sectSpeedTargets[id])<0.0001,'该项目正在锁定，请先停止锁定再修改或撤销')end end
 for id,value in pairs(changes)do
  check(fresh.byID[id] and type(value)=='number' and value==value and math.abs(value)<=1000000,'数值无效或过大')
  work[#work+1]={id=id,value=value,old=fresh.byID[id].value}
 end
 check(#work>0,'没有需要写入的项目');table.sort(work,function(a,b)return a.id<b.id end)
 local base=getAddressSafe('GameAssembly.dll');E.recoverCurrentBridge(base,base+0x18B9460,fresh.context.pid)
 local history={snapshot=fresh,changes={},after={}}
 if not undoing then E.sectBonusUndo=history end
 E.busy=true
 local ok,err=pcall(function()
  E.callSectNative(function(invoke,number,_,float)
   for _,r in ipairs(work)do
    local now=E.sectBonusSnapshot();check(E.sectBonusCompatible(fresh,now),'读档或门派变化，停止写入')
    check(math.abs(now.byID[r.id].value-r.old)<0.0001,'加成已被游戏重算，请刷新后重试')
    history.changes[r.id]=r.old;history.after[r.id]=r.value
    invoke(now.bonus,'Set',{number(r.id),float(r.value)},0x1854D70)
    local after=E.sectBonusSnapshot();check(E.sectBonusCompatible(fresh,after),'写入期间已切换存档')
    check(math.abs(after.byID[r.id].value-r.value)<=math.max(0.0001,math.abs(r.value)*0.000001),'写入未生效或已被重算')
   end
  end)
 end)
 E.busy=nil
 if not ok then error('门派加成操作未全部完成：'..tostring(err)..'。请刷新核对；已尝试的项目保留撤销记录。')end
 if undoing then E.sectBonusUndo=nil end
 return #work
end
function E.stopSectSpeedLock(reason)
 local lock=E.sectSpeedLock;E.sectSpeedLock=nil
 if lock and lock.timer then lock.timer.Enabled=false;lock.timer.OnTimer=nil;lock.timer.destroy()end
 if E.sectLockNotice then E.sectLockNotice(reason or '锁定已停止；当前数值保留，可用撤销恢复启用前的值。')end
end
E.sectSpeedTargets={[4]=99.99,[5]=9.99,[8]=9.99,[9]=9.99,[10]=9.99,[11]=9.99,[12]=99.99,[13]=99.99}
function E.sectSpeedLockTick()
 local lock=E.sectSpeedLock;if not lock or E.busy then return end
 local ok,err=pcall(function()
  local s=E.sectBonusSnapshot();check(E.sectBonusCompatible(lock.snapshot,s),'已读档或切换门派')
  local dict=q(s.bonus+16);local entries=q(dict+24);local version=int(dict+36);local count=int(dict+32);local slots={}
  check(count>=0 and count<1000,'加成字典异常')
  for j=0,count-1 do local e=entries+32+j*16;local h=int(e)
   if h>=0 and h<0x80000000 then local id=int(e+8);if E.sectSpeedTargets[id]then slots[id]=e end end
  end
  for id in pairs(E.sectSpeedTargets)do check(slots[id],'加成条目被移除，请重新开启锁定')end
  for id,value in pairs(E.sectSpeedTargets)do
   check(same(s.context,context()) and int(s.context.hero+0x84)==s.id,'读档或门派变化')
   check(q(s.force+0x148)==s.bonus and q(s.bonus+16)==dict and q(dict+24)==entries and int(dict+36)==version,'加成结构正在重算')
   local e=slots[id];check(int(e)>=0 and int(e)<0x80000000 and int(e+8)==id,'加成条目已变化')
   if math.abs(flt(e+12)-value)>0.0001 then check(writeFloat(e+12,value),'锁定写入失败')end
  end
 end)
 if not ok then E.stopSectSpeedLock('锁定已自动停止：'..tostring(err)..'。请刷新后重新开启。')end
end
function E.startSectSpeedLock(previous)
 check(not E.sectSpeedLock,'锁定已开启');check(not E.busy,'其他操作进行中')
 E.setSectBonuses(previous,E.sectSpeedTargets)
 local fresh=E.sectBonusSnapshot();check(E.sectBonusCompatible(previous,fresh),'存档已变化，未开启锁定')
 local timer=createTimer(nil,false);local lock={snapshot=fresh,timer=timer};E.sectSpeedLock=lock
 timer.Interval=750;timer.OnTimer=E.sectSpeedLockTick;timer.Enabled=true
 return '锁定中：科研、建造、本地建造 +9999%；旅行、疗伤与恢复 +999%。关闭面板或切换存档会停止。'
end

function E.showSectBonuses()
 if E.sectBonusForm then E.sectBonusForm.show();E.sectBonusForm.bringToFront();return end
 local f=createForm(false);E.sectBonusForm=f;f.Caption='门派加成管理 · 当前门派';f.Width=940;f.Height=710;f.Position='poScreenCenter';f.OnClose=function()E.stopSectSpeedLock();return caHide or 1 end
 local function lab(text,x,y)local p=createLabel(f);p.Caption=text;p.Left=x;p.Top=y;return p end
 local status=lab('正在读取门派加成……',16,604);status.Width=890;status.Height=68;status.WordWrap=true
 local function btn(text,x,y,w,fn)local p=createButton(f);p.Caption=text;p.Left=x;p.Top=y;p.Width=w;p.OnClick=function()local ok,err=pcall(fn);if not ok then status.Caption=tostring(err);showMessage(tostring(err))end end;return p end
 lab('搜索名称 / ID',16,17);local search=createEdit(f);search.Left=120;search.Top=12;search.Width=330
 local filter=createComboBox(f);filter.Left=465;filter.Top=12;filter.Width=210;filter.Style='csDropDownList'
 for _,v in ipairs({'全部','速度 / 恢复','经验 / 功绩','资源产量','全员属性','容量 / 上限','领地'})do filter.Items.add(v)end;filter.ItemIndex=0
 local view=createListView(f);view.Left=16;view.Top=52;view.Width=890;view.Height=370;view.ViewStyle='vsReport';view.ReadOnly=true;view.RowSelect=true;view.HideSelection=false
 for _,v in ipairs({{'ID',50},{'名称',230},{'分类',170},{'当前加成',150},{'本次方案',150}})do local col=view.Columns.add();col.Caption=v[1];col.Width=v[2]end
 local detail=lab('选择一项后输入新值。百分比直接填 100，表示加成 +100%。',16,438);detail.Width=890;detail.Height=48;detail.WordWrap=true
 lab('新加成',16,503);local value=createEdit(f);value.Left=90;value.Top=496;value.Width=150;local unit=lab('',250,503)
 local snapshot,visible,selected,planScope;local plan={};local quiet=false
 local function fmt(row,v)return string.format('%.4g',row.percent and v*100 or v)..(row.percent and '%' or '')end
 local function draw()
  quiet=true;view.Items.beginUpdate();view.Items.clear();visible={};selected=nil
  if snapshot then for _,r in ipairs(snapshot.rows)do
   if (filter.ItemIndex==0 or r.group==filter.Text) and (r.name..' '..r.id):find(search.Text or '',1,true)then
    visible[#visible+1]=r;local item=view.Items.add();item.Caption=tostring(r.id);item.SubItems.add(r.name);item.SubItems.add(r.group);item.SubItems.add(fmt(r,r.value));item.SubItems.add(plan[r.id]~=nil and fmt(r,plan[r.id]) or '')
   end
  end end
  view.Items.endUpdate();quiet=false
 end
 local function refresh()
  check(not E.busy,'操作进行中');local fresh=E.sectBonusSnapshot()
  if not E.sectBonusCompatible(planScope,fresh)then plan={};planScope=fresh;E.sectBonusUndo=nil end
  snapshot=fresh;f.Caption='门派加成管理 · '..fresh.name;draw();status.Caption='已读取 65 项。当前汇总加成可能在科技升级、过日或读档后重算；本次方案可重新应用。可用右下角按钮持续锁定速度。'
 end
 search.OnChange=draw;filter.OnChange=draw
 view.OnSelectItem=function(_,_,yes)if yes and not quiet then
  selected=visible[view.ItemIndex+1];if selected then value.Text=string.format('%.6g',selected.percent and selected.value*100 or selected.value);unit.Caption=selected.percent and '% 加成' or '固定加成';detail.Caption=selected.name..'：当前 '..fmt(selected,selected.value)..'。'..(selected.percent and '填 100 = +100%，不是最终倍率；本地项仍遵循游戏作用范围。' or '填写加成量，不是最终总属性。')end
 end end
 btn('刷新',705,10,200,refresh)
 btn('写入选中加成',355,494,180,function()
  check(selected,'请先选中一项');local r=selected;local v=tonumber(((value.Text or ''):gsub('%%','')));check(v,'请输入有效数字');if r.percent then v=v/100 end
  E.setSectBonuses(snapshot,{[r.id]=v});plan[r.id]=v;refresh();status.Caption='已写入「'..r.name..'」。若游戏界面未更新，请重新打开相应页面；重算覆盖后可重新应用方案。'
 end)
 btn('撤销上次写入',555,494,170,function()
  local h=check(E.sectBonusUndo,'没有可撤销的修改');local now=E.sectBonusSnapshot();check(E.sectBonusCompatible(h.snapshot,now),'已切换存档，不能撤销旧数据')
  for id,v in pairs(h.after)do check(math.abs(now.byID[id].value-v)<=math.max(0.0001,math.abs(v)*0.000001),'数值已被重算或另行修改，停止撤销')end
  E.setSectBonuses(now,h.changes,true);for id in pairs(h.changes)do plan[id]=nil end;refresh();status.Caption='已恢复上次写入前的加成。'
 end)
 btn('重新应用本次方案',16,550,240,function()local n=E.setSectBonuses(planScope,plan);refresh();status.Caption='已重新应用 '..n..' 项加成。'end)
 btn('清空方案（不改数值）',280,550,240,function()check(not E.busy,'操作进行中');plan={};draw();status.Caption='方案已清空；当前游戏数值保持不变。'end)
 local lockButton=createButton(f);lockButton.Left=550;lockButton.Top=550;lockButton.Width=355;lockButton.Caption='锁定速度：科研建造9999% / 其余999%'
 E.sectLockNotice=function(msg)lockButton.Caption=E.sectSpeedLock and '停止速度锁定' or '锁定速度：科研建造9999% / 其余999%';status.Caption=msg end
 lockButton.OnClick=function()
  local ok,msg=pcall(function()
   if E.sectSpeedLock then E.stopSectSpeedLock();return end
   local text=E.startSectSpeedLock(check(snapshot,'请先刷新'))
   for id,v in pairs(E.sectSpeedTargets)do plan[id]=v end
   refresh();E.sectLockNotice(text)
  end)
  if not ok then E.sectLockNotice(tostring(msg));showMessage(tostring(msg))end
 end
 f.show();local ok,err=pcall(refresh);if not ok then status.Caption=tostring(err)end
end
