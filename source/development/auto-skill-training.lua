function E.stopAutoSkill(reason)
 local t=E.autoSkill;E.autoSkill=nil
 if t then t.cancel=true;if t.timer then t.timer.Enabled=false;t.timer.OnTimer=nil;t.timer.destroy()end end
 if t and E.skillTraining then E.skillTraining.cancel=true end
 if E.autoSkillNotice then E.autoSkillNotice(false,reason or '连续修炼已停止；已提交的一次操作可能仍会完成。')end
end
function E.randomBreakthrough(snapshot,r,token)
 check(E.autoSkill==token and not token.cancel and not token.submitted,'已停止或本次突破已经提交')
 check(not E.busy,'游戏调用尚未完成')
 local base=getAddressSafe('GameAssembly.dll')
 local recovered=E.recoverCurrentBridge(base,base+0x18B9460,snapshot.context.pid)
 if recovered then
  local saved=LongYiItemBridgeV13
  if saved and saved.pid==recovered.pid and saved.base==recovered.base then
   recovered.clone=saved.clone;recovered.add=saved.add;recovered.objectNew=saved.objectNew
  end
  LongYiItemBridgeV13=recovered
 end
 E.busy=true
 local ok,err=pcall(function()
  E.callSectNative(function(native,number,str)
   local function invoke(obj,name,args,rva)
    check(E.autoSkill==token and not token.cancel and same(snapshot.context,context()),'已停止或切换存档')
    return native(obj,name,args,rva)
   end
   local function yes(obj)return obj and obj~=0 and readBytes(obj+16,1)==1 end
   check(int(snapshot.context.hero+0x58)==0,'仅支持主角，防止NPC重复结算突破奖励')
   check(int(r.ptr+0x10)==r.id and int(r.ptr+0x14)==r.level and r.level<10,'突破目标或等级已改变')
   check(yes(invoke(r.ptr,'CanUpgrade',nil,0x7BB8C0)) and yes(invoke(r.ptr,'SkillMeetObstacleLv',nil,0x7BFEF0)),'尚未达到突破关口')
   local choices=invoke(r.ptr,'GetBreakThroughAvailableChoice',nil,0x7BC6F0)
   check(choices and choices~=0 and int(choices+0x18)>0,'此功法没有可用突破效果')
   local ctrl=q(q(q(base+0x1E937B0)+0xB8)+8);local target=readQword(ctrl+0x18)
   check(not target or target==0 or target==r.ptr,'正在突破另一门武功')
   -- Native red rareLv is 5; ForceFunction 14 adds one strength step.
   -- GetMaxRareLv depends on the temporary preparation score, not the rarity cap.
   local strength=5+(yes(invoke(snapshot.context.hero,'HaveForceFunction',{number(14)},0x5CF4C0)) and 1 or 0)
   if target==r.ptr then
    invoke(ctrl,'CancelInvoke',{str('SetAllBreakChoiceAvailable')})
    invoke(q(ctrl+0x20),'SetActive',{number(0)})
   end
   token.submitted={ptr=r.ptr,level=r.level}
   invoke(r.ptr,'AutoManageBreakThrough',{number(strength)},0x7BB4F0)
   invoke(snapshot.context.hero,'UpgradeSkill',{r.ptr},0x5E1AE0)
   check(int(r.ptr+0x14)==r.level+1,'突破已提交但等级异常，停止；不要重复提交')
   if target==r.ptr then writeQword(ctrl+0x18,0)end
  end)
 end)
 E.busy=nil;if not ok then error(err)end
 return true
end
function E.startAutoSkill(previous,selected)
 check(not E.autoSkill and not E.busy and not E.skillTraining,'请先停止其他修炼或等待操作完成')
 check(selected and selected.level<10,'请选择未满级的武功')
 local token={snapshot=previous,id=selected.id,ptr=selected.ptr,name=selected.name,phase='train',cancel=false}
 local function current()
  local s=E.skillSnapshot();check(same(previous.context,s.context),'已读档或切换角色')
  local r;for _,row in ipairs(s.rows)do if row.id==token.id and row.ptr==token.ptr then r=row;break end end
  check(r,'选中的武功已失效');return s,r
 end
 local s,r=current();check(r.level==selected.level,'等级已变化，请刷新后重新选择')
 local base=getAddressSafe('GameAssembly.dll');local ctrl=q(q(q(base+0x1E937B0)+0xB8)+8);local target=readQword(ctrl+0x18)
 check(not target or target==0 or target==r.ptr,'游戏正在突破另一门武功，请先完成或关闭')
 if target==r.ptr then token.phase='choose';token.deadline=getTickCount()+25000 end
 token.timer=createTimer(nil,false);token.timer.Interval=750;E.autoSkill=token
 local function notice(text)if E.autoSkill==token and E.autoSkillNotice then E.autoSkillNotice(true,token.name..'：'..text)end end
 token.timer.OnTimer=function()
  if token.running or token.cancel or E.autoSkill~=token or E.busy or E.skillTraining or LongYiCustomCallBusy or LongYiWarehouseBusy or LongYiBreakthroughCallBusy then return end
  token.running=true
  local ok,err=pcall(function()
   local fresh,row=current()
   if row.level>=10 then E.stopAutoSkill(token.name..' 已满10级，连续修炼完成。');if E.refreshSkills then E.refreshSkills()end;return end
   if token.phase=='verify' then
    if row.level>token.submitted.level then token.submitted=nil;token.phase='train';notice('突破完成，继续修炼。')
    else check(getTickCount()<token.deadline,'突破提交后等级未增加，停止；未重复点击奖励')end
   elseif token.phase=='open' then
    token.phase='choose';token.deadline=getTickCount()+25000;notice('直接结算随机红色突破，无需显示卡片。')
   elseif token.phase=='choose' then
    check(getTickCount()<token.deadline,'等待奖励超时，请在游戏中核对突破面板')
    local choice=E.randomBreakthrough(fresh,row,token)
    if choice=='prepare' then token.phase='open';notice('准备直接结算红色奖励。')
    elseif choice then token.phase='verify';token.deadline=getTickCount()+8000;notice('随机奖励已提交，正在核对等级。')end
   else
    token.phase='training';notice('正在练到下一个突破关口。')
    E.trainSkillToObstacle(fresh,row,function(success,msg)
     if E.autoSkill~=token or token.cancel then return end
     local good,problem=pcall(function()
      check(success,msg);local nextSnapshot,nextRow=current()
      if nextRow.level>=10 then E.stopAutoSkill(token.name..' 已满10级，连续修炼完成。');if E.refreshSkills then E.refreshSkills()end;return end
      token.phase='open';notice('已练到关口，下一步直接结算红色奖励。')
     end)
     if not good then E.stopAutoSkill('连续修炼停止：'..tostring(problem))end
    end,function(msg)if E.autoSkill==token then notice(msg)end end)
   end
  end)
  token.running=false
  if not ok then E.stopAutoSkill('连续修炼停止：'..tostring(err))end
 end
 token.timer.Enabled=true;notice('连续修炼已开启：升级 → 红色突破 → 随机奖励，直到10级。')
end
