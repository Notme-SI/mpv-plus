local root=mp.command_native({'expand-path','~~/'})
mp.get_script_directory=function()return root..'/scripts/uosc'end
package.path=root..'/scripts/uosc/?.lua;'..package.path
dofile(root..'/scripts/uosc/main.lua')
local function check()
    assert(Elements.controls and Elements.timeline,'Actual uosc elements loaded')
    assert(state.is_idle,'Start without media')
    mp.set_property_native('user-data/player-ui/controls-always',true)
    mp.add_timeout(.3,function()
        local ok,err=xpcall(function()
            assert(Elements.controls:get_visibility()==1,'Idle panel stays visible')
            assert(Elements.timeline.enabled,'Idle rail rendered')
            assert(Elements.timeline:render(),'Idle rail has actual ASS output')
            local top=Elements.top_bar
            top.proximity=1;top.render_titles.main='(unavailable)'
            assert(not top:render().text:find('(unavailable)',1,true),'No unavailable title on the empty screen')
            top.proximity=0
            state.is_idle=false;state.duration=120;state.time=20
            state.time_human='00:20';state.destination_time_human='-01:40'
            Elements.timeline:decide_enabled()
            -- Hovering the timeline used to hide the controls.
            Elements.timeline.is_hovered=true
            for _,element in Elements:ipairs()do element.proximity=0;element.proximity_raw=math.huge;element.forced_visibility=nil end
            assert(Elements.controls:get_visibility()==1,'Timeline hover cannot hide pinned controls')
            local count=0
            for _,control in ipairs(Elements.controls.layout)do
                if control.element and control.element.enabled then
                    assert(control.element:get_visibility()==1,'Actual anchored button stays visible: '..control.element.id..' anchor='..tostring(control.element.anchor_id)..' visibility='..tostring(control.element:get_visibility()))
                    count=count+1
                end
            end
            assert(count>=(Elements.controls.player_layout and 8 or 10),'Bottom row includes actual controls and speed')
            local controls=Elements.controls.controls
            if Elements.controls.player_layout then
                local speed=controls[5].element
                assert(math.abs((speed.ax+speed.bx)/2-display.width/2)<=1,'Speed is centered independently of side groups')
                assert(Elements.timeline.by<Elements.controls.ay,'Timeline sits above the controls')
                local timeline=Elements.timeline
                local rail_left,rail_right=timeline:rail()
                local elapsed,remaining=timeline:clock_centers(rail_left,rail_right)
                local menu,fullscreen=controls[1].element,controls[11].element
                assert(math.abs((menu.ax+menu.bx)/2-elapsed)<=1 and math.abs((fullscreen.ax+fullscreen.bx)/2-remaining)<=1,
                    'Outer buttons align with the time labels')
                for _,control in ipairs(controls) do
                    local button=control.element
                    assert(not button or button.icon~='play_arrow' and button.icon~='pause'
                        and button.icon~='arrow_back_ios' and button.icon~='arrow_forward_ios','Transport is not duplicated below')
                end
                local old_width=display.width
                display.width=300
                Elements.controls:update_dimensions()
                assert(speed.enabled,'Compact windows keep the centered speed control')
                display.width=old_width
                Elements.controls:update_dimensions()
            end
            assert(Elements.timeline:get_visibility()==1 and Elements.timeline:render(),'Active seek rail stays rendered')
            assert(keybind_to_human('Alt+p')=='ALT+P' and keybind_to_human('Ctrl+з')=='CTRL+З','Shortcut labels use uppercase')
            state.time_human='00:26:53';state.destination_time_human='-01:58:07'
            local rail=Elements.timeline:render().text
            assert(rail:find('26:53',1,true) and rail:find('1:58:07',1,true)
                and not rail:find('00:26:53',1,true) and not rail:find('-01:58:07',1,true),'Timeline labels use compact unsigned clocks')
            state.has_audio=true
            for _,id in ipairs({'top_bar','volume'})do
                local element=assert(Elements[id])
                assert(element:get_visibility()==0,id..' still hides without the cursor')
                element.proximity=1
                assert(element:get_visibility()==1,id..' still appears on hover')
                element.proximity=0;element.forced_visibility=.4
                assert(element:get_visibility()==.4,id..' keeps its native fade')
                element.forced_visibility=nil
                assert(element:get_visibility()==0,id..' fades out with the bottom panel pinned')
            end
            local volume=Elements.volume
            volume.proximity=1
            local glyphs=dofile(root..'/extensions/lucide_glyphs.lua')
            local icons=0
            for event in volume:render().text:gmatch('[^\n]+')do
                if event:find(glyphs.volume_up,1,true)then
                    local _,positions=event:gsub('\\pos%(','')
                    assert(positions==1,'Speaker has its own ASS position instead of the panel origin')
                    icons=icons+1
                end
            end
            assert(icons==2,'Both speaker layers retain their own render events')
            local indicator=Elements.pause_indicator
            state.is_video=true;state.pause=true
            state.has_playlist=true;state.playlist_pos=2;state.playlist_count=3
            local zone=cursor.zone
            local clicks={}
            cursor.zone=function(_,key,_,callback) if key=='primary_click' then clicks[#clicks+1]=callback end end
            local ok_center,result=pcall(indicator.render,indicator)
            cursor.zone=zone
            assert(ok_center and result and result.text:find('\\1c&H161616&',1,true) and #clicks==3,'Paused video has three clickable transport controls')
            local _,discs=result.text:gsub('\\1c&Hf4f4f4&','')
            assert(discs==3,'Previous, next and play use the same light disc and dark symbol')
            mp.set_property_bool('pause',true);clicks[3]()
            assert(not mp.get_property_bool('pause'),'Clicking the center control resumes playback')
            state.pause=false;state.is_video=false
            volume.proximity=0
            top.proximity=1;top.render_titles.main='Example title'
            local title=top:render().text
            assert(title:find('Example title',1,true) and title:find('2 / 3',1,true),'Loaded title and playlist position remain visible')
            state.has_playlist=false;state.playlist_pos=0;state.playlist_count=0
            top.current_chapter={title='Hidden chapter',index=1}
            state.chapters={{title='Hidden chapter',time=0},{title='Next chapter',time=30}}
            local header=top:render().text
            assert(not header:find('Hidden chapter',1,true) and not header:find('0:10',1,true),'No chapter or chapter timer in the upper panel')
            top.proximity=0
            Elements.curtain.opacity=1
            assert(Elements.controls:get_visibility()==0,'Menu still intercepts interactions')
            Elements.curtain.opacity=0
            mp.set_property_native('user-data/player-ui/controls-always',false)
            mp.add_timeout(.2,function()
                Elements.timeline.is_hovered=true
                if Elements.controls.player_layout then
                    local timeline,panel=Elements.timeline,Elements.controls
                    assert(panel:get_visibility()==0 and timeline:get_visibility()==0,'Both hide away from the bottom area')
                    timeline.proximity=1
                    assert(panel:get_visibility()==1 and timeline:get_visibility()==1 and panel.controls[5].element:get_visibility()==1,
                        'Hovering the timeline also shows the buttons and speed')
                    timeline.proximity=0;panel.proximity=1
                    assert(panel:get_visibility()==1 and timeline:get_visibility()==1,'Hovering the controls also shows the timeline')
                    panel.proximity=0
                    timeline.forced_visibility=1
                    assert(panel:get_visibility()==1 and timeline:get_visibility()==1,'Flashing the timeline reveals the entire row')
                    timeline.forced_visibility=nil
                    local top=panel.controls[10].element
                    assert(top.icon=='pin_off','The default layout uses the pin when always-on-top is off')
                else
                    assert(Elements.controls:get_visibility()==-1,'A custom layout retains native timeline hover behavior')
                end
                Elements.timeline.is_hovered=false;state.is_idle=true;state.duration=nil;state.time=nil
                Elements.timeline:decide_enabled()
                assert(not Elements.timeline.enabled,'Idle rail disabled again when option off')
                print('PINNED_PANEL_REAL_UOSC_OK buttons='..count)
                mp.commandv('quit',0)
            end)
        end,debug.traceback)
        if not ok then print('PINNED_PANEL_FAILED '..err);mp.commandv('quit',1)end
    end)
end
mp.add_timeout(.5,check)
mp.add_timeout(8,function()print('PINNED_PANEL_TIMEOUT');mp.commandv('quit',1)end)
