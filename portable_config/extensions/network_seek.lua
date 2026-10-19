-- Coalesce network scrubbing; the final release always performs an exact seek.
return function(Timeline)
    local seek,release,leave=Timeline.set_from_cursor,Timeline.handle_cursor_up,Timeline.on_global_mouse_leave
    local function network()return mp.get_property_bool('demuxer-via-network',false) or (mp.get_property('path',''):match('https?://')~=nil)end
    function Timeline:set_from_cursor(fast,final)
        if self.pressed and network() then
            local now=mp.get_time()
            if not final and self.network_seek_time and now-self.network_seek_time<.2 then return end
            self.network_seek_time=now
            return seek(self,not final)
        end
        return seek(self,fast)
    end
    function Timeline:handle_cursor_up()
        if self.pressed and network() then self:set_from_cursor(false,true) end
        self.network_seek_time=nil;release(self)
    end
    function Timeline:on_global_mouse_leave()
        if self.pressed then self:handle_cursor_up() else leave(self) end
    end
end
