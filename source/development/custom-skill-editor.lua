local function withGame(action)
if LongYiCustomCallBusy then error("上次调用尚未完成")end
local function check(v,s)if not v then error(s,2)end;return v end
local function q(a)return check(readQword(a),'指针不可读')end
local function int(a)return check(readInteger(a),'数据不可读')end
local function cstr(a)return readString(a,180) or ''end
local function ustr(a)if a==0 then return ''end;local n=int(a+16);check(n<4096,'文字长度异常');return readString(a+20,n*2,true) or ''end
local function classname(p)return cstr(q(q(p)+16))end
local pid=getOpenedProcessID();local base=check(getAddressSafe('GameAssembly.dll'),'请连接游戏并读入存档')
local update=base+0x18B9460;local original=readBytes(update,6,true);check(original and #original==6,'Update 不可读')
local function matches(a,b)if not a or not b or #a~=#b then return false end;for n=1,#a do if a[n]~=b[n]then return false end end;return true end
local chain
if not matches(original,{0x40,0x53,0x48,0x83,0xEC,0x40})then
 for _,name in ipairs({'LongYiItemBridgeV13','LongYiItemBridgeV12','LongYiItemBridgeV11','LongYiItemBridgeV10'})do
  local b=_G[name]
  if b and b.pid==pid and b.base==base and matches(original,b.patch)then
   check(int(b.data)~=1 and int(b.data)~=2,'请等当前物品操作结束');chain=b.mem;break
  end
 end
 check(chain,'Update 被其他脚本修改；请先停用冲突脚本或重启游戏，未覆盖原入口')
end
local pe=int(base+0x3C);local e=base+int(base+pe+0x88);local exports={}
for n=0,int(e+0x18)-1 do
 local name=cstr(base+int(base+int(e+0x20)+n*4))
 if name:find('il2cpp_',1,true)==1 then local ord=readSmallInteger(base+int(e+0x24)+n*2);exports[name]=base+int(base+int(e+0x1C)+ord*4)end
end
local function method(obj,name,argc,rva)
 local k=q(obj)
 while k~=0 do
  local tab=q(k+0x98)
  for n=0,2047 do
   local m=readQword(tab+n*8);if not m or m==0 or readQword(m+24)~=k then break end
   if cstr(q(m+16))==name and readBytes(m+0x4A,1)==argc and q(m)~=0 and (not rva or q(m)==base+rva)then return m end
  end
  k=q(k+0x58)
 end
 error('找不到接口：'..name)
end
LongYiCustomCallBusy=true
local mem=allocateMemory(0x10000,update)
if not mem then LongYiCustomCallBusy=nil;error('无法分配临时调用区')end
local d=mem+0x2000;local cursor=mem+0x3000;local handles={};local attached=false;local patch;local created
local regs={'rax','rcx','rdx','rbx','rbp','rsi','rdi','r8','r9','r10','r11','r12','r13','r14','r15'}
local asm={'label(done)','label(noroot)',string.format('%X:',mem),'pushfq'}
for _,r in ipairs(regs)do asm[#asm+1]='push '..r end
asm[#asm+1]='sub rsp,A8'
for n=0,5 do asm[#asm+1]=string.format('movdqu [rsp+%X],xmm%d',n==0 and 0x80 or 0x20+n*16,n)end
asm[#asm+1]=string.format([[
mov rbx,%X
cmp dword ptr [rbx],1
jne done
mov dword ptr [rbx],2
mov rcx,[rbx+18]
mov rdx,[rbx+20]
mov r8,[rbx+28]
mov r9,[rbx+30]
mov rax,[rbx+38]
mov [rsp+20],rax
mov rax,[rbx+10]
call rax
mov [rbx+8],rax
cmp dword ptr [rbx+48],1
jne noroot
mov rcx,rax
xor edx,edx
mov rax,%X
call rax
mov [rbx+40],eax
noroot:
mov dword ptr [rbx],3
done:]],d,check(exports.il2cpp_gchandle_new,'缺少 IL2CPP 导出'))
for n=0,5 do asm[#asm+1]=string.format('movdqu xmm%d,[rsp+%X]',n,n==0 and 0x80 or 0x20+n*16)end
asm[#asm+1]='add rsp,A8'
for n=#regs,1,-1 do asm[#asm+1]='pop '..regs[n]end
asm[#asm+1]='popfq'
asm[#asm+1]=chain and string.format('jmp %X',chain) or string.format('push rbx\nsub rsp,40\njmp %X',update+6)
local function call(fn,args,root)
 check(int(d)~=2,'上一次调用尚未完成')
 writeQword(d+8,0);writeQword(d+16,fn)
 for n=1,5 do writeQword(d+0x10+n*8,args and args[n] or 0)end
 writeInteger(d+0x48,root and 1 or 0);writeInteger(d,1)
 local start=getTickCount()
 while int(d)~=3 do
  if getTickCount()-start>5000 then if int(d)==1 then writeInteger(d,0)end;error('游戏未完成调用；请回到游戏运行，不要重复勾选')end
  sleep(10);processMessages()
 end
 if root then handles[#handles+1]=int(d+0x40)end
 return q(d+8)
end
local function blob(bytes)
 local a=cursor;cursor=math.floor((cursor+#bytes+15)/16)*16;check(cursor<mem+0x10000,'临时参数区已满')
 check(writeBytes(a,bytes),'参数写入失败');return a
end
local function number(v)local a=blob({0,0,0,0,0,0,0,0});writeInteger(a,v);return a end
local function vector(values)local bytes={};for _=1,#values*4 do bytes[#bytes+1]=0 end;local a=blob(bytes);for n,v in ipairs(values)do writeFloat(a+(n-1)*4,v)end;return a end
local function str(s)local a={s:byte(1,#s)};a[#a+1]=0;return call(exports.il2cpp_string_new,{blob(a)},true)end
local function invoke(m,obj,args)
 local a=0;if args and #args>0 then local bytes={};for _=1,#args*8 do bytes[#bytes+1]=0 end;a=blob(bytes);for n,v in ipairs(args)do writeQword(a+(n-1)*8,v)end end
 local ex=blob({0,0,0,0,0,0,0,0});local result=call(exports.il2cpp_runtime_invoke,{m,obj,a,ex});check(q(ex)==0,'游戏接口报告异常');return result
end
local function invokeNamed(obj,name,args,rva)return invoke(method(obj,name,args and #args or 0,rva),obj,args)end
local function transform(go)return invokeNamed(go,'get_transform')end
local function getgo(tr)return invokeNamed(tr,'get_gameObject')end
local function getchild(tr,n)return invokeNamed(tr,'GetChild',{number(n)})end
local function count(tr)return int(invokeNamed(tr,'get_childCount')+16)end
local ok,err=pcall(function()
 check(autoAssemble(table.concat(asm,'\n')),'临时调用代码编译失败')
 check(math.abs(mem-update)<0x7FFFFFF0,'临时调用区距离过远')
 check(matches(readBytes(update,6,true),original),'入口已变化')
 check(autoAssemble(string.format('%X:\njmp %X\nnop',update,mem)),'临时入口安装失败');attached=true;patch=readBytes(update,6,true)
 action(invokeNamed,number,str,function(v)return vector({v})end)
end)
if attached and int(d)~=2 then
 for _,h in ipairs(handles)do pcall(call,exports.il2cpp_gchandle_free,{h})end
 if matches(readBytes(update,6,true),patch)then writeBytes(update,original)else ok=false;err='入口已变化，未覆盖其他脚本'end
elseif attached then ok=false;err=tostring(err)..'；调用仍在执行，保留临时调用区，勿重复操作'end
-- Scratch pages remain until process exit so no returning game frame uses freed code.
LongYiCustomCallBusy=nil
if not ok then error(err)end

end
local function need(v,msg)if not v then error(msg,2)end;return v end
local function q(a)return need(readQword(a),'指针失效，请重新读取')end
local function int(a)return need(readInteger(a),'整数不可读')end
local function txt(p)if p==0 then return ''end;local n=int(p+16);need(n<4096,'字符串异常');return readString(p+20,n*2,true) or ''end
local function context()
 local b=need(getAddressSafe('GameAssembly.dll'),'请连接游戏');local k=q(b+0x1E9BAC0)
 need(readString(q(k+16),80)=='CustomSkillCreateController','游戏版本不匹配')
 local st=q(k+0xB8);local c=q(st);need(c~=0,'请先读档')
 return {base=b,pid=getOpenedProcessID(),ctrl=c,statics=st,draft=q(c+0x28)}
end
-- Unity serializes an empty default object before the first creation session.
local function hasDraft(c)
 local p=c.draft
 if p==0 then return false end
 return txt(q(p+0x20))~='' or txt(q(p+0x28))~='' or txt(q(p+0xD0))~='' or (readFloat(p+0x40) or 0)>0
end

local function budgetOverride(value)
 local b=need(getAddressSafe('GameAssembly.dll'),'请连接游戏');local a=b+0x657850;local pid=getOpenedProcessID()
 local original={0x40,0x53,0x48,0x83,0xEC,0x20,0x80,0x3D,0xAA,0xF2}
 local function eq(x,y)if not x or not y or #x~=#y then return false end;for i=1,#x do if x[i]~=y[i]then return false end end;return true end
 local state=LongYiCustomBudget
 if state and state.pid~=pid then LongYiCustomBudget=nil;state=nil end
 local current=readBytes(a,10,true)
 need(eq(current,state and state.patch or original),'预算函数已被其他脚本改动，未覆盖')
 if not value then
  if state then need(writeBytes(a,state.original),'恢复失败');LongYiCustomBudget=nil end
  return
 end
 local bytes={string.pack('<f',value):byte(1,4)}
 local code={0xB8,bytes[1],bytes[2],bytes[3],bytes[4],0x66,0x0F,0x6E,0xC0,0xC3}
 need(writeBytes(a,code),'预算覆盖失败')
 LongYiCustomBudget={pid=pid,address=a,patch=code,original=original,value=value}
end
LongYiRestoreCustomBudget=function()budgetOverride(nil)end
if LongYiCustomEditor then pcall(function()LongYiCustomEditor.destroy()end)end
local f=createForm(false);LongYiCustomEditor=f;f.Caption='自创武功编辑器 v6 · 效果位置与目标';f.Width=920;f.Height=760;f.Position='poScreenCenter';f.OnClose=function()return caHide or 1 end
local function label(s,x,y)local z=createLabel(f);z.Caption=s;z.Left=x;z.Top=y;return z end
local function edit(x,y,w)local z=createEdit(f);z.Left=x;z.Top=y;z.Width=w;return z end
local function combo(x,y,w,items)local z=createComboBox(f);z.Left=x;z.Top=y;z.Width=w;z.Style='csDropDownList';for _,v in ipairs(items)do z.Items.add(v)end;z.ItemIndex=0;return z end
local status=label('选择模板新建草稿，或读取游戏中已打开的草稿。',16,710);status.Width=880
local busy=false
local function button(s,x,y,w,fn)local z=createButton(f);z.Caption=s;z.Left=x;z.Top=y;z.Width=w;z.OnClick=function()if busy then return end;busy=true;local ok,e=pcall(fn);busy=false;if not ok then status.Caption=tostring(e);showMessage(tostring(e))end end;return z end
local templates={};local c=context();local m=q(q(q(c.base+0x1E528F8)+0xB8)+0x20);local d=q(m+0x138);local count=int(d+32);need(count<20000,'配置长度异常')
for n=0,count-1 do local e=q(d+24)+32+n*24;local h=int(e);if h>=0 and h<0x80000000 then local p=q(e+16);if readBytes(p+0x10,1)==0 then templates[#templates+1]={id=int(e+8),name=txt(q(p+32)),description=txt(q(p+40)),kind=int(p+0x30),rarity=int(p+0x34),damage=readFloat(p+0x3C),mana=readFloat(p+0x38),icon=txt(q(p+0xD0))}end end end
table.sort(templates,function(a,b)return a.id<b.id end)
local selectedTemplate
local templateLabel=label('尚未选择模板。点击「搜索模板」查看说明。',16,38);templateLabel.Width=495
label('模板（选择只预览，不会改动当前草稿）',16,12)
local kinds={'内功','轻功','绝技','拳掌','剑法','刀法','长兵','奇门','射术'}
local tiers={'基础','进阶','上乘','秘传','顶级','绝世'}
local picker
local function openPicker()
 if picker then picker.show();picker.bringToFront();return end
 picker=createForm(false);picker.Caption='选择自创武功模板 v3 · 搜索 / 筛选 / 说明';picker.Width=1000;picker.Height=720;picker.Position='poScreenCenter';picker.OnClose=function()return caHide or 1 end
 local function lab(text,x,y)local o=createLabel(picker);o.Caption=text;o.Left=x;o.Top=y;return o end
 lab('名称 / ID / 描述',14,12)
 local search=createEdit(picker);search.Left=14;search.Top=34;search.Width=475
 local function filter(x,w,title,values)
  lab(title,x,12);local o=createComboBox(picker);o.Left=x;o.Top=34;o.Width=w;o.Style='csDropDownList';o.Items.add('全部');for _,v in ipairs(values)do o.Items.add(v)end;o.ItemIndex=0;return o
 end
 local kfilter=filter(510,170,'类别',kinds);local rfilter=filter(700,170,'品阶',tiers)
 local view=createListView(picker);view.Left=14;view.Top=78;view.Width=960;view.Height=320;view.ViewStyle='vsReport';view.ReadOnly=true;view.RowSelect=true;view.HideSelection=false
 for _,v in ipairs({{'ID',85},{'名称',310},{'类别',130},{'品阶',130},{'基础伤害',130},{'内力消耗',130}})do local col=view.Columns.add();col.Caption=v[1];col.Width=v[2]end
 local memo=createMemo(picker);memo.Left=14;memo.Top=414;memo.Width=960;memo.Height=210;memo.ReadOnly=true;memo.ScrollBars='ssVertical';memo.WordWrap=true;memo.Lines.Text='选择一行查看模板说明。'
 local info=lab('',14,715);info.Width=950
 local visible={};local choice;local drawing=false
 local function select()
  if drawing then return end
  choice=view.Selected and visible[view.Selected.Index+1] or nil
  if not choice then memo.Lines.Text='选择一行查看模板说明。';return end
  local t=choice
  memo.Lines.Text=t.name..'  /  ID '..t.id..'\r\n'..(kinds[t.kind+1] or tostring(t.kind))..' · '..(tiers[t.rarity+1] or tostring(t.rarity))..'\r\n基础伤害 '..tostring(t.damage)..'    内力消耗 '..tostring(t.mana)..'\r\n\r\n'..(t.description~='' and t.description or '此模板没有文字说明。')..'\r\n\r\n说明：以上是原模板配置。新建时游戏会重置名称、伤害和部分特效，最终以草稿为准。'
 end
 local function draw()
  drawing=true;choice=nil;visible={};view.Items.beginUpdate();view.Items.clear()
  local term=search.Text:lower()
  for _,t in ipairs(templates)do
   if (kfilter.ItemIndex==0 or t.kind==kfilter.ItemIndex-1) and (rfilter.ItemIndex==0 or t.rarity==rfilter.ItemIndex-1) and (term=='' or (t.id..' '..t.name..' '..t.description):lower():find(term,1,true))then
    visible[#visible+1]=t;local row=view.Items.add();row.Caption=tostring(t.id);row.SubItems.add(t.name);row.SubItems.add(kinds[t.kind+1] or tostring(t.kind));row.SubItems.add(tiers[t.rarity+1] or tostring(t.rarity));row.SubItems.add(tostring(t.damage));row.SubItems.add(tostring(t.mana))
   end
  end
  view.Items.endUpdate();drawing=false;memo.Lines.Text='选择一行查看模板说明。';info.Caption='显示 '..#visible..' / '..#templates..' 个模板；筛选和预览只使用缓存，不调用游戏接口。'
 end
 local use=createButton(picker);use.Left=744;use.Top=638;use.Width=230;use.Caption='使用选中模板（不创建）';use.OnClick=function()select();if not choice then showMessage('请先选择模板');return end;selectedTemplate=choice;templateLabel.Caption=choice.id..' · '..choice.name..' · '..(tiers[choice.rarity+1] or '');picker.hide()end
 view.OnSelectItem=function(_,_,selected)if selected then select()end end
 search.OnChange=draw;kfilter.OnChange=draw;rfilter.OnChange=draw
 draw();picker.show()
end
f.OnDestroy=function()if picker then pcall(function()picker.destroy()end);picker=nil end end
button('搜索模板 / 查看说明',735,32,165,openPicker)
label('功法名称',16,86);local name=edit(16,108,300)
label('功法描述',340,86);local desc=edit(340,108,550)
label('品阶',16,150);local rarity=combo(16,172,180,{'基础','进阶','上乘','稀有','顶级','绝世'})
label('基础伤害',220,150);local damage=edit(220,172,140)
label('经验倍率',380,150);local exp=edit(380,172,140)
label('战斗使用次数（0不限）',550,150);local uses=edit(550,172,180)
label('最终武学预算上限（可直接提高）',16,216);local budget=edit(16,238,180)
label('当前品阶特效数量上限',220,216);local limit=edit(220,238,180)
label('保存后直接覆盖最终上限；取消勾选恢复游戏预算规则。',430,242)
local rangeNames={'菱形距离','方形','十字直线','对角线','定向直线','扇形','定向斜线','全攻击范围','定向交叉'}
label('攻击范围（第一段）',16,288);local atk=combo(16,310,230,rangeNames);local amin=edit(260,310,85);local amax=edit(360,310,85)
label('最小距离',260,288);label('最大距离',360,288)
label('作用范围',16,354);local area=combo(16,376,230,rangeNames);local rmin=edit(260,376,85);local rmax=edit(360,376,85)
label('最小距离',260,354);label('最大距离',360,354)
label('已有特效：带 % 的直接填百分数，例如连击填 20 = 20%',16,424)
local effects=combo(16,448,510,{});local effectValue=edit(545,448,120)
local snap,attack,range,addresses={},nil,nil,{}
local percentFlags={}
local function numeric(box,lo,hi,integer)local v=tonumber(box.Text);need(v and v==v and v>=lo and v<=hi and (not integer or v==math.floor(v)),'请输入 '..lo..' 到 '..hi..' 的'..(integer and '整数' or '数值'));return v end
local editorPID=c.pid
local function refresh()
 need(getOpenedProcessID()==editorPID,'游戏进程已变化，请关闭并重新勾选编辑器')
 snap=context();need(hasDraft(snap),'当前是未初始化的空草稿，请选择模板并点击新建')
 local p=snap.draft;name.Text=txt(q(p+32));desc.Text=txt(q(p+40));rarity.ItemIndex=int(p+0x34);damage.Text=tostring(readFloat(p+0x3c));exp.Text=tostring(readFloat(p+0x40));uses.Text=tostring(int(p+0x84))
 local tier=rarity.ItemIndex;local off=int(p+0x30)<3 and 0x18 or 0x20
 budget.Text=tostring(LongYiCustomBudget and LongYiCustomBudget.pid==snap.pid and LongYiCustomBudget.value or 1000);limit.Text=tostring(int(q(snap.statics+8)+32+tier*4))
 local list=q(p+0x70);attack=nil;if list~=0 and int(list+24)>0 then attack=q(q(list+16)+32)end
 range=q(p+0x78)
 if attack then atk.ItemIndex=int(attack+16);amin.Text=tostring(int(attack+20));amax.Text=tostring(int(attack+24))else amin.Text='0';amax.Text='0' end
 if range~=0 then area.ItemIndex=int(range+16);rmin.Text=tostring(int(range+20));rmax.Text=tostring(int(range+24))end
 effects.Items.clear();addresses={};percentFlags={};local spe=q(p+(int(p+0x30)<3 and 0x60 or 0x68));local dict=q(spe+16);local total=int(dict+32);need(total<1000,'特效数据异常')
 local labels=q(m+0x90);local arr=q(labels+16)
 for n=0,total-1 do local e=q(dict+24)+32+n*16;local hash=int(e);if hash>=0 and hash<0x80000000 then local id=int(e+8);local percent=false;local title='特效 '..id;if id>=0 and id<int(labels+24)then local conf=q(arr+32+id*8);title=txt(q(conf+16));percent=readBytes(conf+0x38,1)==1 end;percentFlags[#percentFlags+1]=percent;addresses[#addresses+1]=e+12;effects.Items.add(title..(percent and ' (%)' or '（数值）'))end end
 effects.ItemIndex=#addresses>0 and 0 or -1;effectValue.Text=#addresses>0 and string.format('%.6g',readFloat(addresses[1])*(percentFlags[1] and 100 or 1)) or ''
 status.Caption='已读取草稿；类别 '..int(p+0x30)..'，内力 '..tostring(readFloat(p+0x38))..'。保存后在游戏确认创建。'
end
effects.OnChange=function()local a=addresses[effects.ItemIndex+1];effectValue.Text=a and string.format('%.6g',readFloat(a)*(percentFlags[effects.ItemIndex+1] and 100 or 1)) or ''end
local function sameDraft()local c=context();need(c.pid==snap.pid and c.draft==snap.draft and c.draft~=0,'草稿已变化，请重新读取');return c end


button('全部效果：搜索 / 添加 / 删除',490,286,380,function()
 local c=sameDraft();local draft=c.draft
 local ef=createForm(false);ef.Caption='全效果目录 v6 · 触发 / 目标 / 写入位置';ef.Width=980;ef.Height=780;ef.Position='poScreenCenter'
 local function lab(t,x,y)local l=createLabel(ef);l.Caption=t;l.Left=x;l.Top=y;return l end
 lab('名称 / ID / 说明',14,12);local search=createEdit(ef);search.Left=14;search.Top=34;search.Width=450
 lab('写入位置（按效果用途建议筛选）',490,12)
 local scope=createComboBox(ef);scope.Left=490;scope.Top=34;scope.Width=460;scope.Style='csDropDownList'
 for _,t in ipairs({'装备效果：装备后持有的属性 / 被动','施放效果：攻击或使用时触发','升级效果：每级累加的成长值'})do scope.Items.add(t)end
 scope.ItemIndex=int(draft+0x30)<3 and 0 or 1
 local offsets={0x60,0x68,0x58};local catalog={};local visible={};local chosen;local drawing=false
 local manager=q(q(q(c.base+0x1E528F8)+0xB8)+32);local list=q(manager+0x90);local arr=q(list+16);local total=int(list+24);need(total>0 and total<5000,'效果目录长度异常')
 for id=0,total-1 do
  local conf=q(arr+32+id*8)
  if conf~=0 then
   local title=txt(q(conf+16));local description=txt(q(conf+24)):gsub('\\n','\r\n')
   local percent=readBytes(conf+0x38,1)==1
   catalog[#catalog+1]={id=id,name=title~='' and title or ('未命名效果 '..id),description=description,percent=percent,default=readFloat(conf+0x20),trigger=int(conf+0x54),target=txt(q(conf+0x48)),selfBuff=readBytes(conf+0x40,1)==1,noAuto=readBytes(conf+0x50,1)==1}
  end
 end
 local advanced=createCheckBox(ef);advanced.Left=14;advanced.Top=68;advanced.Width=650;advanced.Caption='高级：显示全部，允许非建议位置写入（不改变效果作用对象）'
 local view=createListView(ef);view.Left=14;view.Top=100;view.Width=936;view.Height=310;view.ViewStyle='vsReport';view.ReadOnly=true;view.RowSelect=true;view.HideSelection=false
 for _,v in ipairs({{'ID',45},{'效果',110},{'单位',45},{'当前数值',85},{'触发',95},{'目标分类',90},{'位置建议',130},{'说明摘要',300}})do local col=view.Columns.add();col.Caption=v[1];col.Width=v[2]end
 local memo=createMemo(ef);memo.Left=14;memo.Top=422;memo.Width=936;memo.Height=190;memo.ReadOnly=true;memo.WordWrap=true;memo.ScrollBars='ssVertical'
 lab('目标数值（百分比直接填 20 表示 20%）',14,626);local value=createEdit(ef);value.Left=14;value.Top=652;value.Width=220
 local info=lab('',14,715);info.Width=936
 local function currentDict()
  local now=sameDraft();need(now.draft==draft,'草稿已改变，请关闭并重新打开效果窗口')
  local holder=q(draft+offsets[scope.ItemIndex+1]);need(holder~=0,'当前草稿缺少此效果容器')
  return q(holder+16)
 end
 local function existing()
  local dict=currentDict();local count=int(dict+32);need(count>=0 and count<5000,'效果字典异常');local a=q(dict+24);local out={}
  for n=0,count-1 do local e=a+32+n*16;local hash=int(e);if hash>=0 and hash<0x80000000 then out[int(e+8)]=readFloat(e+12)end end
  return out
 end
 local function recommended(t,index)
  if index==0 then return true end
  if index==1 then return t.trigger==1 end
  return t.trigger==0 and not t.noAuto
 end
 local function triggerText(t)return ({[0]='属性 / 被动',[1]='攻击触发',[2]='受击触发'})[t.trigger] or ('触发 '..t.trigger)end
 local function targetText(t)return t.target=='伤害' and '伤害 / 通用' or t.target end
 local function suggestion(t)
  if t.trigger==1 then return '施放 / 装备触发'
  elseif t.trigger==2 then return '装备：受击触发'
  elseif t.noAuto then return '装备（非自动成长）'
  else return '装备 / 升级成长' end
 end
 local function showChoice()
  if drawing then return end
  chosen=view.Selected and visible[view.Selected.Index+1] or nil
  if not chosen then value.Text='';return end
  local t=chosen;local current=existing()[t.id];local factor=t.percent and 100 or 1
  value.Text=string.format('%.6g',(current~=nil and current or t.default)*factor)
  memo.Lines.Text=t.name..' / ID '..t.id..'\r\n'..(t.percent and '百分比：输入 20 = 20%' or '普通数值：直接填写数值')..'\r\n\r\n'..(t.description~='' and t.description or '游戏配置没有文字说明。')..'\r\n\r\n触发：'..triggerText(t)..'；目标分类：'..targetText(t)..'；建议：'..suggestion(t)..'。'..'\r\n'..(scope.ItemIndex==2 and '这里填写每一级的增量，不是总值；非建议效果的成长处理未经验证。' or scope.ItemIndex==0 and '装备位置保存持有者的属性和被动；具体触发仍按效果自身配置。' or '施放位置不会把持续恢复改成攻击吸血，也不会改变目标阵营。')..'\r\n'..(recommended(t,scope.ItemIndex) and '这是按配置推导的位置建议，实际效果仍取决于游戏战斗逻辑。' or '非建议位置：默认不允许新增或修改；可删除已有项，或启用高级模式。')..((t.id>=152 and t.id<=155) and '\r\n回血 / 回内 / 回体 / 自愈是每回合恢复，建议放装备或升级成长。要攻击回血，请搜索游戏原有的吸血或吸取效果。' or '')
 end
 local function draw()
  local values=existing();local term=search.Text:lower();drawing=true;visible={};chosen=nil;view.Items.beginUpdate();view.Items.clear()
  for _,t in ipairs(catalog)do
   if (advanced.Checked or recommended(t,scope.ItemIndex) or values[t.id]~=nil) and (term=='' or (t.id..' '..t.name..' '..t.description..' '..triggerText(t)..' '..targetText(t)):lower():find(term,1,true))then
    visible[#visible+1]=t;local r=view.Items.add();r.Caption=tostring(t.id);r.SubItems.add(t.name);r.SubItems.add(t.percent and '%' or '数值')
    r.SubItems.add(values[t.id]~=nil and string.format('%.6g',values[t.id]*(t.percent and 100 or 1)) or '未添加');r.SubItems.add(triggerText(t));r.SubItems.add(targetText(t));r.SubItems.add((recommended(t,scope.ItemIndex) and '' or '非建议 · ')..suggestion(t));r.SubItems.add(t.description:gsub('[\r\n]+',' '))
   end
  end
  view.Items.endUpdate();drawing=false;value.Text='';memo.Lines.Text='选择效果查看触发与目标。已有非建议项仍显示，方便删除；切换位置不会搬移原效果。';info.Caption='显示 '..#visible..' / '..#catalog..' 项。按写入用途筛选，不限制内功、轻功、剑法；高级模式可显示全部。'
 end
 local function operate(deleting)
  if busy then return end;busy=true
  local ok,err=pcall(function()
   local t=need(chosen,'请先选中效果');local dict=currentDict();local v
   if deleting then need(existing()[t.id]~=nil,'当前位置尚未添加此效果')else need(advanced.Checked or recommended(t,scope.ItemIndex),'此效果不建议写入当前位置；请选择建议位置，或显式启用高级模式');v=numeric(value,-1000000,1000000,false)/(t.percent and 100 or 1)end
   withGame(function(invoke,number,str,float)
    need(currentDict()==dict,'效果字典已变化，请刷新')
    if deleting then invoke(dict,'Remove',{number(t.id)},0x1687e20)else invoke(dict,'set_Item',{number(t.id),float(v)},0x1707560)end
   end)
   local actual=existing()[t.id]
   need(deleting and actual==nil or not deleting and actual~=nil and math.abs(actual-v)<=math.max(1e-6,math.abs(v)*1e-6),'效果写入后校验失败')
   draw();info.Caption=(deleting and '已删除：' or '已添加 / 更新：')..t.name..'。数值已回读验证；游戏面板可能需刷新。'
  end)
  busy=false;if not ok then info.Caption=tostring(err);showMessage(tostring(err))end
 end
 local add=createButton(ef);add.Left=260;add.Top=650;add.Width=220;add.Caption='添加 / 更新选中效果';add.OnClick=function()operate(false)end
 local del=createButton(ef);del.Left=500;del.Top=650;del.Width=210;del.Caption='删除当前位置的效果';del.OnClick=function()operate(true)end
 local reload=createButton(ef);reload.Left=730;reload.Top=650;reload.Width=220;reload.Caption='刷新已有数值';reload.OnClick=function()local ok,e=pcall(draw);if not ok then showMessage(tostring(e))end end
 search.OnChange=function()local ok,e=pcall(draw);if not ok then info.Caption=tostring(e)end end;scope.OnChange=search.OnChange;advanced.OnChange=search.OnChange
 view.OnSelectItem=function(_,_,selected)if selected then local ok,e=pcall(showChoice);if not ok then info.Caption=tostring(e)end end end
 draw();ef.show()
end)
button('伤害加成系数（自由修改）',490,350,380,function()
 local c=sameDraft();local p=c.draft;local ratio=q(p+0x48)
 local rf=createForm(false);rf.Caption='伤害加成系数 · 0 禁用 / 可超出游戏档位';rf.Width=800;rf.Height=590;rf.Position='poScreenCenter'
 local rows={}
 local function lab(s,x,y)local z=createLabel(rf);z.Caption=s;z.Left=x;z.Top=y end
 lab('直接输入原始系数，不受中 / 上档位限制。例如剑法 2 可改为 10；0 表示不加成。',12,12)
 local groups={{offset=16,names={'力道','灵巧','智力','意志','体质','经脉'}},{offset=24,names={'内功','轻功','绝技','拳掌','剑法','刀法','长兵','奇门','射术'}},{offset=32,names={'医术','毒术','学识','口才','采伐','木植','锻造','炼药','烹饪'}}}
 for g,spec in ipairs(groups)do
  local list=q(ratio+spec.offset);need(int(list+24)==#spec.names,'加成列表长度不匹配');local arr=q(list+16)
  for n,title in ipairs(spec.names)do
   local x=12+(g-1)*260;local y=52+(n-1)*40;local address=arr+32+(n-1)*4
   lab(title,x,y+4);local box=createEdit(rf);box.Left=x+70;box.Top=y;box.Width=160;box.Text=string.format('%.6g',readFloat(address))
   rows[#rows+1]={box=box,address=address,list=list,array=arr}
  end
 end
 for n,v in ipairs({{'生命',0x28},{'体力',0x2C},{'内力',0x30},{'魅力',0x34}})do
  local x=12+(n-1)*195;lab(v[1],x,430);local box=createEdit(rf);box.Left=x;box.Top=452;box.Width=170;box.Text=string.format('%.6g',readFloat(ratio+v[2]));rows[#rows+1]={box=box,address=ratio+v[2]}
 end
 local save=createButton(rf);save.Caption='写入所有加成系数';save.Left=510;save.Top=510;save.Width=260
 save.OnClick=function()
  if busy then return end;busy=true
  local ok,err=pcall(function()
   local now=sameDraft();need(now.draft==p and q(p+0x48)==ratio,'草稿已经变化，请重新打开系数窗口')
   local values={};for n,r in ipairs(rows)do values[n]=numeric(r.box,-100000,100000,false);if r.list then need(q(r.list+16)==r.array,'加成列表已变化，请重开')end end
   withGame(function(invoke)
    for n,r in ipairs(rows)do need(writeFloat(r.address,values[n]),'系数写入失败')end
    invoke(c.ctrl,'RefreshSkillPointText',{},0x659a00)
   end)
   status.Caption='伤害加成已写入。游戏中/上文字可能仍用旧显示，以此窗口回读系数为准。';rf.close()
  end)
  busy=false;if not ok then showMessage(tostring(err))end
 end
 rf.show()
end)
button('恢复游戏预算规则',490,390,380,function()budgetOverride(nil);status.Caption='已恢复原预算规则；再次保存表单会重新启用指定预算。'end)
button('写入选中特效',685,446,180,function()sameDraft();local a=need(addresses[effects.ItemIndex+1],'请选择已有特效');local v=numeric(effectValue,-100000,100000,false);writeFloat(a,v/(percentFlags[effects.ItemIndex+1] and 100 or 1));status.Caption='已写入特效；保存表单时刷新游戏显示。'end)
label('全效果目录标明触发和目标；默认按位置筛选，高级模式保留跨类别添加。',16,495)
label('预算覆盖影响所有自创草稿；数量按品阶修改。已创建作品不会被撤销。',16,530)
label('本窗口不自动确认创作。最终请在游戏里检查名称、范围与效果后点击确认。',16,558)
button('读取当前草稿',16,622,180,refresh)
button('按模板新建草稿',540,32,180,function()
 local c=context();need(not hasDraft(c),'已有有效草稿：请先读取；如不需要，请点丢弃并重建');local t=need(selectedTemplate,'请选择模板')
 withGame(function(invoke,number)invoke(c.ctrl,'ShowCreatePanel',{number(t.id)},0x65a6c0)end);refresh()
end)
button('丢弃草稿并按模板重建',540,622,270,function()
 local c=context();local t=need(selectedTemplate,'请选择模板')
 if hasDraft(c) and messageDialog('只丢弃当前未确认草稿，按 '..t.name..' 重新初始化。是否继续？',mtConfirmation,mbYes,mbNo)~=mrYes then return end
 withGame(function(invoke,number)invoke(c.ctrl,'ShowCreatePanel',{number(t.id)},0x65a6c0)end);refresh()
end)
button('保存表单到草稿',220,622,220,function()
 local c=sameDraft();local p=c.draft;local tier=rarity.ItemIndex;need(tier>=0 and tier<=5,'请选择品阶')
 local dmg=numeric(damage,0,100000,false);local xp=numeric(exp,0.01,1000,false);local us=numeric(uses,0,10000,true);local bd=numeric(budget,1,100000,true);local lm=numeric(limit,1,100,true)
 local mn=numeric(amin,0,100,true);local mx=numeric(amax,0,100,true);local rn=numeric(rmin,0,100,true);local rx=numeric(rmax,0,100,true);need(mx>=mn and rx>=rn,'最大距离不得小于最小距离');need(#name.Text>0,'请输入功法名称')
 withGame(function(invoke,number,str)
  sameDraft();writeInteger(p+0x34,tier);writeFloat(p+0x3c,dmg);writeFloat(p+0x40,xp);writeInteger(p+0x84,us)
  budgetOverride(bd);writeInteger(q(c.statics+8)+32+tier*4,lm)
  if attack then writeInteger(attack+16,atk.ItemIndex);writeInteger(attack+20,mn);writeInteger(attack+24,mx)end
  if range~=0 then writeInteger(range+16,area.ItemIndex);writeInteger(range+20,rn);writeInteger(range+24,rx)end
  invoke(q(c.ctrl+0x30),'set_text',{str(name.Text)},0x167ef30);invoke(q(c.ctrl+0x38),'set_text',{str(desc.Text)},0x167ef30)
  invoke(c.ctrl,'ResetSkillName',{},0x65a420);invoke(c.ctrl,'ResetSkillDescribe',{},0x65a220)
  invoke(c.ctrl,'RefreshBaseDamageUI',{},0x6590d0);invoke(c.ctrl,'RefreshDamageRangeUI',{},0x6593b0);invoke(c.ctrl,'RefreshSpeAddDataGrid',{},0x659c60);invoke(c.ctrl,'RefreshSkillPointText',{},0x659a00)
 end)
 status.Caption='已写入草稿并刷新游戏；请在游戏最终确认创建。'
end)
f.show()
if hasDraft(c) then local ok,e=pcall(refresh);if not ok then status.Caption=tostring(e)end end
