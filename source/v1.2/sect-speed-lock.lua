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
