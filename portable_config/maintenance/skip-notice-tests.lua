return function(path)
 local real=mp
 local ui=package.loaded['mpv-build/ui_locale']
 local time,timers,events,observers,bindings=0,{},{},{},{}
 local props={['time-pos']=126,['idle-active']=false,['user-data/player-ui/icon-style']='glass',['mouse-pos']={hover=false}}
 local overlay={update=function()end,remove=function()end}
 local clicks=0
 local function get(k,d)if props[k]==nil then return d end;return props[k]end
 local function advance(seconds)
  time=time+seconds
  for _,timer in ipairs(timers)do if timer.active and timer.at<=time then timer.active=false;timer.fn()end end
 end
 local mock={command_native=function(a)return path(a[2]:gsub('^~~/',''))end,
  get_property_number=get,get_property_native=get,get_property_bool=get,get_osd_size=function()return 1280,720 end,
  create_osd_overlay=function()return overlay end,set_property_native=function(k,v)props[k]=v end,
  get_time=function()return time end,
  add_forced_key_binding=function(_,name,fn)bindings[name]=fn end,remove_key_binding=function(name)bindings[name]=nil end,
  commandv=function(...) local a={...};assert(a[1]=='script-message-to' and a[3]=='skip-active');clicks=clicks+1 end,
  observe_property=function(k,kind,fn)observers[k]=fn end,register_event=function(k,fn)events[k]=fn end,
  add_timeout=function(delay,fn)local t={at=time+delay,active=true,fn=fn,kill=function(self)self.active=false end};timers[#timers+1]=t;return t end}
 local ok,err=xpcall(function()
  mp=mock;package.loaded['mpv-build/ui_locale']={language=function()return 'ru'end,text=function(v)return v end}
  dofile(path('scripts/skip_prompt.lua'))
  for _,kind in ipairs({'intro','recap','credits','preview'})do
   observers['user-data/skip-prompt'](nil,{kind=kind,start=35,['end']=125,auto=true,notice=true})
   assert(props['user-data/skip-prompt-visible'] and overlay.data:find('Автопропуск:',1,true),'Post-seek notice not visible: '..kind)
   advance(2.9);observers['user-data/skip-prompt'](nil,{})
   assert(props['user-data/skip-prompt-visible'],'Late empty update shortened notice: '..kind)
   advance(.11);assert(not props['user-data/skip-prompt-visible'],'Notice exceeded 3 seconds: '..kind)
  end
  props.seeking=true
  observers['user-data/skip-prompt'](nil,{kind='intro',start=35,['end']=125,auto=true,notice=true})
  observers.seeking();advance(8)
  observers['user-data/skip-prompt'](nil,{})
  assert(props['user-data/skip-prompt-visible'],'Buffering consumed the notice')
  props['paused-for-cache']=true;props.seeking=false;observers.seeking()
  advance(8);assert(props['user-data/skip-prompt-visible'],'Waiting for cache consumed the notice')
  props['paused-for-cache']=false;observers['paused-for-cache']();events['playback-restart']()
  advance(2.9);assert(props['user-data/skip-prompt-visible'],'Notice ended before three seconds after playback resumed')
  advance(.11);assert(not props['user-data/skip-prompt-visible'])
  observers['user-data/skip-prompt'](nil,{kind='intro',start=35,['end']=125,auto=true,notice=true})
  events['end-file']();assert(not props['user-data/skip-prompt-visible'],'Old notice leaked to next media')
  advance(4);assert(not props['user-data/skip-prompt-visible'])
  props['time-pos']=33.9
  observers['user-data/skip-prompt'](nil,{id='manual',kind='intro',start=35,['end']=125})
  assert(not props['user-data/skip-prompt-visible'],'Prompt appeared more than a second early')
  props['time-pos']=34;observers['time-pos']()
  assert(props['user-data/skip-prompt-visible'],'One-second preview was not rendered')
  assert(props['user-data/skip-prompt-ready'].id=='manual','Missing render acknowledgement')
  local box=props['user-data/skip-prompt-box'];props['mouse-pos']={x=box.x0+5,y=box.y0+5}
  observers['mouse-pos']();assert(bindings.click,'Preview must be clickable before the segment')
  bindings.click({event='press'})
  assert(clicks==1 and not props['user-data/skip-prompt-visible'],'Manual click must hide immediately')
  observers['user-data/skip-prompt'](nil,{id='manual',kind='intro',start=35,['end']=125})
  props['time-pos']=125;observers['time-pos']()
  assert(not props['user-data/skip-prompt-visible'],'Manual seek outside segment must hide prompt')
 end,debug.traceback)
 mp=real;package.loaded['mpv-build/ui_locale']=ui;assert(ok,err)
end
