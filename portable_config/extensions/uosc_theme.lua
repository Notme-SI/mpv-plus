-- Local rendering layer. No upstream files or interaction bindings are replaced.
return function(extend)
    local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
    local glass=dofile(mp.command_native({'expand-path','~~/extensions/glass_surface.lua'}))
    local metrics=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/text_metrics.lua').new()
    local T={mode='glass',marks=true,metadata={badges={}},title={}}
    local artwork=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/title_artwork.lua').new(
        mp.command_native({'expand-path','~~/'}),function() if request_render then request_render() end end)
    mp.observe_property('user-data/uosc/menu/type','string',function(_,value)
        if value and value~='' then artwork.hide() end
    end)
    mp.observe_property('user-data/readable-title','native',function(_,value)
        T.title=value or {}
        if request_render then request_render() end
    end)
    function T.glass() return T.mode=='glass' end
    mp.observe_property('user-data/player-ui','native',function(_,value)
        value=value or {}
        T.mode=value['icon-style'] or 'glass'
        T.marks=value['chapter-marks']~=false
        if request_render then request_render() end
    end)
    mp.observe_property('user-data/media-info','native',function(_,value)
        T.metadata=value or {badges={}}
        if Elements then Elements:maybe('top_bar','update_dimensions') end
        if request_render then request_render() end
    end)
    function T.panel(ass,box,visibility,radius,hover,primary)
        if T.glass() then glass.panel(ass,{x0=box.ax,y0=box.ay,x1=box.bx,y1=box.by},state.scale,visibility,radius,hover,primary)
        else ass:rect(box.ax,box.ay,box.bx,box.by,{color='000000',radius=radius,opacity=(hover and .76 or primary and .66 or .52)*visibility}) end
    end
    function T.transport(ass,x,y,r,icon,opacity)
        -- The desktop icon has a light disc with a dark, filled play triangle.
        ass:circle(x,y,r*.53,{color='f4f4f4',opacity=opacity})
        local dark={color='161616',opacity=opacity}
        if icon=='pause' then
            dark.radius=r*.035
            ass:rect(x-r*.19,y-r*.22,x-r*.07,y+r*.22,dark)
            ass:rect(x+r*.07,y-r*.22,x+r*.19,y+r*.22,dark)
        else
            ass:new_event()
            ass:append(string.format('{\\rDefault\\an7\\pos(0,0)\\bord0\\shad0\\1c&H161616&%s}',ass.opacity(nil,opacity)))
            ass:draw_start()
            ass:move_to(x-r*.14,y-r*.24)
            ass:line_to(x+r*.25,y)
            ass:line_to(x-r*.14,y+r*.24)
            ass:draw_stop()
        end
    end
    function T.header(ass,box,visibility)
        T.panel(ass,box,visibility,math.min(10*state.scale,(box.by-box.ay)/2))
    end
    function T.rail_style(visibility)
        return {color=T.glass() and 'd0d0d0' or '000000',border=0.6*state.scale,border_color='ffffff',
            opacity={main=(T.glass() and 0.24 or 0.48)*visibility,border=(T.glass() and 0.24 or 0.10)*visibility}}
    end
    local shortcut_commands={
        menu='script-binding uosc/menu',cloud='script-binding torrserver_loader/torr_open',
        list_alt='script-binding uosc/playlist',graphic_eq='script-binding uosc/audio',
        subtitles='script-binding uosc/subtitles',window_normal='cycle ontop',window_on_top='cycle ontop',
        crop_free='cycle fullscreen',fullscreen_exit='cycle fullscreen',
    }
    local function keyboard_hint(icon)
        local command=shortcut_commands[icon]
        if not command then return end
        local active={}
        for _,binding in ipairs(mp.get_property_native('input-bindings',{})) do
            local key,priority=binding.key,binding.priority
            if key and priority and priority>=0 and not key:match('MBTN') and not key:match('WHEEL')
                and key~='MENU' and (not active[key] or priority>active[key].priority) then
                active[key]=binding
            end
        end
        local best
        for key,binding in pairs(active) do
            if binding.cmd==command and (not best or binding.priority>best.priority
                or binding.priority==best.priority and key<best.key) then best=binding end
        end
        return best and best.key
    end
    function T.tooltip(ass,button,label,key,visibility,grouped)
        local s=state.scale
        local size=13*s*options.font_scale
        local height=math.max(size+10*s,24*s)
        local pad=8*s
        local margin=6*s+Elements:v('window_border','size',0)
        local key_width=key and metrics.width(key,size*.88,config.font,true)+9*s or 0
        local limit=display.width-2*(pad+margin)-key_width
        if limit<=size then return end
        label=metrics.fit(label,limit,size,config.font,false)
        local width=math.min(display.width-2*margin,metrics.width(label,size,config.font,false)+2*pad+key_width)
        local x=clamp(margin,(button.ax+button.bx-width)/2,display.width-margin-width)
        local above=grouped and Elements:v('timeline','ay',button.ay) or button.ay
        local y=above-height-5*s
        if y<margin then y=clamp(margin,button.by+5*s,math.max(margin,display.height-margin-height)) end
        local box={ax=x,ay=y,bx=x+width,by=y+height}
        if T.glass() then glass.menu(ass,{x0=x,y0=y,x1=box.bx,y1=box.by},s,visibility,8*s)
        else T.panel(ass,box,visibility,6*s,true) end
        local cy=y+height/2
        ass:txt(x+pad,cy,4,ass_escape(label),{size=size,color='ffffff',opacity=visibility,bold=false})
        if key then
            local bx=box.bx-4*s
            local ax=bx-key_width+3*s
            ass:rect(ax,y+4*s,bx,box.by-4*s,{color='ffffff',radius=4*s,opacity=.16*visibility})
            ass:txt((ax+bx)/2,cy,5,ass_escape(key),{size=size*.88,color='ffffff',opacity=visibility,bold=true})
        end
    end
    extend('Button',function(Button)
        function Button:render()
            local visibility=self:get_visibility()
            if visibility<=0 then return end
            cursor:zone('primary_click',self,function() self:handle_cursor_click() end)
            local ass,s=assdraw.ass_new(),state.scale
            local hover=self.proximity_raw<=0
            local cx,cy=(self.ax+self.bx)/2,(self.ay+self.by)/2
            local r=math.min(self.bx-self.ax,self.by-self.ay)/2-0.7*s
            local box={ax=cx-r,ay=cy-r,bx=cx+r,by=cy+r}
            local grouped=self.anchor_id=='controls' and Elements:v('controls','player_layout')
            T.panel(ass,box,visibility,r,hover)
            if self.active then ass:circle(cx,cy,r,{color='ffffff',border=.7*s,border_color='ffffff',opacity={main=0,border=.55*visibility}}) end
            if hover and self.tooltip then
                local now=mp.get_time()
                if self.hint_icon~=self.icon or now>=(self.hint_until or 0) then
                    self.hint_icon,self.hint_until=self.icon,now+1
                    self.hint_key=keyboard_hint(self.icon)
                end
                T.tooltip(ass,self,ui.text(self.tooltip),self.hint_key,visibility,grouped)
            end
            local color='ffffff'
            local icon_clip
            if self.badge then
                local size=self.font_size*0.6
                local width=math.ceil(text_width(self.badge,{size=size})+size/3)
                local height=math.ceil(size)
                local bx,by=self.bx-1,self.by-1
                ass:rect(bx-width,by-height,bx,by,{color='ffffff',radius=3*s,border=0,
                    border_color='222222',opacity=visibility})
                ass:txt(bx-width/2,by-height/2,5,self.badge,{size=size,color='111111',opacity=visibility})
                icon_clip=string.format('\\iclip(%d,%d,%d,%d)',math.floor(bx-width-s),math.floor(by-height-s),math.ceil(bx),math.ceil(by))
            end
            local icon_size=self.font_size*(grouped and .86 or .92)
            ass:icon(cx+(self.icon=='play_arrow' and r*.07 or 0),cy,icon_size,self.icon,{color=color,opacity=visibility,border=0,
                border_color='111111',clip=icon_clip})
            return ass
        end
    end)
    extend('TopBar',function(TopBar)
        local decide=TopBar.decide_enabled
        function TopBar:decide_enabled()
            decide(self)
            if not self.enabled then artwork.hide() end
        end
        local dimensions=TopBar.update_dimensions
        function TopBar:update_dimensions()
            dimensions(self)
            if #(T.metadata.badges or {})>0 then
                self.by=math.max(self.by,self.ay+self.size+self.chapter_size-options.proximity_in)
            end
        end
        function TopBar:render()
            local visibility=self:get_visibility()
            if visibility<=0 then artwork.hide();return end
            local ass,s=assdraw.ass_new(),state.scale
            local ax,ay,bx,by=self.ax,self.ay,self.bx,self.ay+self.size
            local margin=math.floor((self.size-self.font_size)/4)
            local left=options.top_bar_controls=='left'
            if options.top_bar_controls then
                local x=left and ax or bx-self.size*#self.buttons
                if left then ax=x+self.size*#self.buttons else bx=x end
                for _,button in ipairs(self.buttons) do
                    local hit={ax=x,ay=ay,bx=x+self.size,by=by}
                    local hover=get_point_to_rectangle_proximity(cursor,hit)<=0
                    cursor:zone('primary_click',hit,button.command)
                    local size=self.size-margin
                    local box={ax=x+(left and margin or 0),ay=ay+margin,
                        bx=x+(left and margin or 0)+size,by=ay+margin+size}
                    local foreground='ffffff'
                    T.panel(ass,box,visibility,size/2,hover)
                    ass:icon((box.ax+box.bx)/2,(box.ay+box.by)/2,size*0.5,button.icon,
                        {color=foreground,border_color=bg,border=0,opacity=visibility})
                    x=x+self.size
                end
            end
            local x,y,limit=ax+12*s,ay+12*s,bx-8*s
            if state.is_idle or options.top_bar_title=='no' or limit-x<110*s then
                artwork.hide();self.title_by=by;return ass
            end
            local default_title=options.top_bar_title=='${user-data/readable-title/text:${media-title}}' and not self.show_alt_as_main
            local main=default_title and (T.title.subtitle and T.title.display_name or T.title.text)
            local subtitle=default_title and T.title.subtitle or nil
            local fallback=self.render_titles.main
            local alternate=options.top_bar_alt_title_place=='below' and self.render_titles.alt or nil
            if (not main or main=='') and (not fallback or fallback=='') then
                artwork.hide();self.title_by=by;return ass
            end
            local main_size=math.max(18*s,self.font_size*1.12)
            local small_size=math.max(11*s,self.font_size*.69)
            local title_h,sub_h,meta_h=math.max(27*s,main_size*1.35),22*s,21*s
            local width_limit=math.min(limit-x,640*s)
            local logo_x=x+9*s
            local logo_w=math.min(limit-logo_x,200*s)
            local logo_h=logo_w*216/640
            local has_art=default_title and Elements.curtain.opacity==0
                and artwork.show(logo_x,y,logo_w,logo_h)
            if not has_art then artwork.hide() end
            local padding,gap=7*s,4*s
            local function chip(value,left,top,size,height,bold,color,escaped,max_width,icon,compact)
                local pad=compact and 4*s or padding
                if not value or value=='' or max_width<=2*pad+size then return end
                local icon_width=icon and size+6*s or 0
                local inset=2*pad+icon_width+2*s
                local needed=metrics.width(value,size,config.font,bold)+inset
                local width=math.min(max_width,needed)
                local box={ax=left,ay=top,bx=left+width,by=top+height}
                T.header(ass,box,visibility)
                if icon then ass:icon(left+padding+size/2,top+height/2,size,icon,{color=color,opacity=visibility}) end
                if not escaped then
                    if needed>max_width then value=metrics.fit(value,max_width-inset,size,config.font,bold) end
                    value=ass_escape(value)
                end
                local text_x=compact and left+width/2 or left+pad+icon_width
                ass:txt(text_x,top+height/2,compact and 5 or 4,value,{size=size,bold=bold,color=color,opacity=visibility,wrap=2,
                    clip=string.format('\\clip(%d,%d,%d,%d)',math.floor(left),math.floor(top),math.floor(box.bx-pad/2),math.ceil(box.by))})
                return box
            end
            local toggle=options.top_bar_alt_title_place=='toggle'
            local row=y
            if has_art then
                if toggle then cursor:zone('primary_click',{ax=logo_x,ay=y,bx=logo_x+logo_w,by=y+logo_h},function()self:toggle_title()end) end
                row=y+logo_h+gap
            else
                local has_title=main and main~=''
                local title=chip(has_title and main or fallback,x,row,main_size,title_h,true,'ffffff',not has_title,width_limit)
                if title and toggle then cursor:zone('primary_click',title,function()self:toggle_title()end) end
                row=row+title_h+gap
            end
            local next_x=x
            if state.has_playlist and state.playlist_pos>0 then
                local position=chip(state.playlist_pos..' / '..state.playlist_count,x,row,small_size,sub_h,true,'ffffff',false,width_limit,nil,true)
                if position then
                    cursor:zone('primary_click',position,function()mp.command('script-binding uosc/playlist')end)
                    next_x=position.bx+gap
                end
            end
            if subtitle then
                if next_x>x and metrics.width(subtitle,small_size,config.font,false)+2*padding+2*s>x+width_limit-next_x then
                    next_x=x;row=row+sub_h+gap
                end
                chip(subtitle,next_x,row,small_size,sub_h,false,'ffffff',false,x+width_limit-next_x)
            end
            if next_x>x or subtitle then row=row+sub_h+gap end
            if alternate then chip(alternate,x,row,small_size,sub_h,false,'ffffff',true,width_limit);row=row+sub_h+gap end
            next_x=x
            local function media_chip(value,icon)
                local width=metrics.width(value,small_size,config.font,false)+2*padding+2*s+(icon and small_size+6*s or 0)
                if next_x>x and next_x+width>x+width_limit then next_x=x;row=row+meta_h+gap end
                local box=chip(value,next_x,row,small_size,meta_h,false,'dfdfdf',false,x+width_limit-next_x,icon)
                if box then next_x=box.bx+gap end
            end
            for _,badge in ipairs(T.metadata.summary or {}) do
                local icon=({video='local_movies',audio='graphic_eq'})[badge.kind]
                if badge.text then
                    local line=''
                    local available=width_limit-2*padding-2*s-(icon and small_size+6*s or 0)
                    for field in (badge.text..' · '):gmatch('(.-) · ') do
                        local joined=line=='' and field or line..' · '..field
                        if line~='' and metrics.width(joined,small_size,config.font,false)>available then
                            media_chip(line,icon)
                            next_x=x;row=row+meta_h+gap
                            line=field
                        else line=joined end
                    end
                    if line~='' then media_chip(line,icon) end
                end
            end
            self.title_by=row+(next_x>x and meta_h or 0)
            self.by=math.max(self.ay+self.size,self.title_by-options.proximity_in)
            return ass
        end
    end)
    function T.menu(Menu)
        local render=Menu.render
        function Menu:render()
            local factory=assdraw.ass_new
            assdraw.ass_new=function(...)
                local ass=factory(...)
                local rect=ass.rect
                ass.rect=function(target,ax,ay,bx,by,opts)
                    if opts and opts.color==bg and opts.radius~=nil and not opts.clip then
                        local visibility=opts.opacity/math.max(.01,config.opacity.menu)
                        if T.glass() then
                            glass.menu(target,{x0=ax,y0=ay,x1=bx,y1=by},state.scale,visibility,opts.radius)
                        else rect(target,ax,ay,bx,by,{color='000000',radius=opts.radius,opacity=.52*visibility}) end
                    elseif T.glass() and opts and opts.color==fg and opts.radius~=nil then
                        local copy={};for k,v in pairs(opts)do copy[k]=v end
                        copy.border=.65*state.scale;copy.border_color='ffffff'
                        copy.opacity={main=math.min(opts.opacity,.22*self.opacity),
                            border=math.min(.42*self.opacity,opts.opacity+.10*self.opacity)}
                        rect(target,ax,ay,bx,by,copy)
                    else rect(target,ax,ay,bx,by,opts) end
                end
                for _,name in ipairs({'txt','icon'})do
                    local draw=ass[name]
                    ass[name]=function(target,x,y,a,b,opts)
                        if T.glass() and opts and (opts.color==fgt or opts.color==bg)then
                            local copy={};for k,v in pairs(opts)do copy[k]=v end
                            copy.color='ffffff';opts=copy
                        end
                        return draw(target,x,y,a,b,opts)
                    end
                end
                return ass
            end
            local ok,result=pcall(render,self)
            assdraw.ass_new=factory
            if not ok then error(result) end
            return result
        end
    end
    return T
end
