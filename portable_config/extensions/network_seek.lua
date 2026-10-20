-- Commit a network scrub once on release. Repeated preview seeks invalidate
-- HTTP ranges and can keep TorrServer refilling ranges the player abandoned.
return function(Timeline)
    local seek,release,leave=Timeline.set_from_cursor,Timeline.handle_cursor_up,Timeline.on_global_mouse_leave
    local function network()return mp.get_property_bool('demuxer-via-network',false) or (mp.get_property('path',''):match('https?://')~=nil)end
    function Timeline:set_from_cursor(fast,final)
        if self.pressed and network() then
            if not final then return end
            return seek(self,false)
        end
        return seek(self,fast)
    end
    function Timeline:handle_cursor_up()
        if self.pressed and network() then self:set_from_cursor(false,true) end
        release(self)
    end
    function Timeline:on_global_mouse_leave()
        if self.pressed then self:handle_cursor_up() else leave(self) end
    end
end
