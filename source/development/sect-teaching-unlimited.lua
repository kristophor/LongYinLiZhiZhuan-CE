-- Only the two sect teaching paths; no shared interaction setter is patched.
if syntaxcheck then return end
local key='LongYiSectTeachingUnlimited'
local sites={
 {0x2A2E8E,'44 8B 40 30 41 FF C8 E8 76 12 4D 01'},
 {0x2A2EE4,'44 8B 40 6C 41 FF C8 E8 20 12 4D 01'},
 {0x2A3696,'44 8B 40 58 41 FF C8 E8 6E 0A 4D 01'},
 {0x2A36DF,'44 8B 40 70 41 FF C8 E8 25 0A 4D 01'}
}
local function need(v,msg)if not v then error(msg,2)end;return v end
local function q(a)return need(readQword(a),'指针不可读，请读档后重试')end
local function num(a)return need(readInteger(a),'数据不可读')end
local function worldNow(base)return q(q(q(q(base+0x1E52870)+0xB8))+0x20)end
-- The wrapper supplies an explicit phase; do not infer CE checkbox timing.
local disabling=LongYiSectTeachingDisable==true
LongYiSectTeachingDisable=nil
if disabling then
 local state=_G[key];if not state then return end
 if getOpenedProcessID()~=state.pid then _G[key]=nil;return end
 local lines={}
 for _,s in ipairs(sites)do
  local address=state.base+s[1]+4
  lines[#lines+1]=string.format('assert(%X,90 90 90)',address)
 end
 for _,s in ipairs(sites)do lines[#lines+1]=string.format('%X:\ndb 41 FF C8',state.base+s[1]+4)end
 local ok,err=autoAssemble(table.concat(lines,'\n'));need(ok,'无法还原指教开关：'..tostring(err))
 _G[key]=nil;return
end
need(not _G[key],'指点 / 传授解除已开启，请先取消原开关')
local pid=getOpenedProcessID();local base=need(getAddressSafe('GameAssembly.dll'),'请先连接游戏')
local world=worldNow(base);local heroes=q(world+0x50);local array=q(heroes+0x10);local count=num(heroes+0x18)
need(count>0 and count<20000,'角色列表异常')
local hero=q(array+0x20);local force=num(hero+0x84);need(force>=0 and force<0x80000000,'主角尚未加入门派')
local restored={}
for j=0,count-1 do
 local h=q(array+0x20+j*8)
 if h~=0 and num(h+0x84)==force then
  local interaction=q(h+0x308);local list=q(interaction+0x10);local a=q(list+0x10);local n=num(list+0x18)
  need(n>=21 and n<=128,'互动次数结构不符')
  for _,index in ipairs({4,14,19,20})do
   local address=a+0x20+index*4;local value=num(address)
   if value<=0 or value>=0x80000000 then restored[#restored+1]={hero=h,interaction=interaction,list=list,array=a,address=address,before=value}end
  end
 end
end
local lines={}
for _,s in ipairs(sites)do lines[#lines+1]=string.format('assert(%X,%s)',base+s[1],s[2])end
for _,s in ipairs(sites)do lines[#lines+1]=string.format('%X:\ndb 90 90 90',base+s[1]+4)end
local ok,err=autoAssemble(table.concat(lines,'\n'));need(ok,'游戏版本或指令不符，未开启：'..tostring(err))
_G[key]={pid=pid,base=base,world=world,restored=restored}
for _,v in ipairs(restored)do writeInteger(v.address,1)end
