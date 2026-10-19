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
            state.is_idle=false;state.duration=120;state.time=20
            state.time_human='00:20';state.destination_time_human='-01:40'
            Elements.timeline:decide_enabled()
            -- The native Controls implementation used to force-hide on timeline hover.
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
            assert(count>=10,'Bottom row includes actual controls and speed')
            assert(Elements.timeline:get_visibility()==1 and Elements.timeline:render(),'Active seek rail stays rendered')
            Elements.curtain.opacity=1
            assert(Elements.controls:get_visibility()==0,'Menu still intercepts interactions')
            Elements.curtain.opacity=0
            mp.set_property_native('user-data/player-ui/controls-always',false)
            mp.add_timeout(.2,function()
                Elements.timeline.is_hovered=true
                assert(Elements.controls:get_visibility()==-1,'Switch off restores native timeline hover behavior')
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
