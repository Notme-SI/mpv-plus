return function(path)
 local real=mp
 local names={'class','trim','split','itable_index_of','itable_find','request_render'}
 local old={};for _,name in ipairs(names)do old[name]=_G[name]end
 local prior=package.loaded['elements/Button']
 local props={ontop='no',geometry='1200x675+70+80',fullscreen='no',border='no',aid=3,sid=4}
 local writes,changed=0,nil
 local ok,err=xpcall(function()
  class=function(base)return setmetatable({},{__index=base})end
  trim=function(v)return v:match('^%s*(.-)%s*$')end
  split=function(v)return {v}end
  itable_index_of=function(list,v)for i,x in ipairs(list)do if x==v then return i end end end
  itable_find=function(list,fn)for i,x in ipairs(list)do if fn(x)then return i end end end
  request_render=function()end
  package.loaded['elements/Button']={init=function()end}
  mp={set_property=function(name,value)
   assert(name=='ontop','Pinning must only change ontop');writes=writes+1;props[name]=value;changed(name,value)
  end}
  local Button=dofile(path('scripts/uosc/elements/CycleButton.lua'))
  local button=setmetatable({observe_mp_property=function(_,name,kind,callback)changed=callback;callback(name,props[name])end},{__index=Button})
  button:init('ontop',{prop='ontop',states={{value='no',icon='flip_to_front',active=false},{value='yes',icon='flip_to_front',active=true}}})
  assert(not button.active);button.on_click();assert(props.ontop=='yes' and button.active)
  button.on_click();assert(props.ontop=='no' and not button.active and writes==2)
  changed('ontop','yes');assert(button.active,'Button must follow changes outside its own click handler')
  assert(props.geometry=='1200x675+70+80' and props.fullscreen=='no' and props.border=='no' and props.aid==3 and props.sid==4)
 end,debug.traceback)
 mp=real;package.loaded['elements/Button']=prior
 for _,name in ipairs(names)do _G[name]=old[name]end
 assert(ok,err)
end
