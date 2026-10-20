-- Local rendering layer. No upstream files or interaction bindings are replaced.
return function(extend)
    local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
    local glass=dofile(mp.command_native({'expand-path','~~/extensions/glass_surface.lua'}))
    local metrics=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/text_metrics.lua').new()
    local T={mode='glass',marks=true,metadata={badges={}}}
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
    function T.panel(ass,box,visibility,radius,hover)
        if T.glass() then glass.panel(ass,{x0=box.ax,y0=box.ay,x1=box.bx,y1=box.by},state.scale,visibility,radius,hover)
        else ass:rect(box.ax,box.ay,box.bx,box.by,{color='000000',radius=radius,opacity=(hover and .64 or .52)*visibility}) end
    end
    function T.header(ass,box,visibility,playlist)
        T.panel(ass,box,visibility,5*state.scale)
    end
    function T.rail_style(visibility)
        return {color=T.glass() and 'd0d0d0' or '000000',border=0.6*state.scale,border_color='ffffff',
            opacity={main=(T.glass() and 0.24 or 0.48)*visibility,border=(T.glass() and 0.24 or 0.10)*visibility}}
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
            T.panel(ass,box,visibility,r,hover)
            if self.active then ass:circle(cx,cy,r,{color='ffffff',border=.7*s,border_color='ffffff',opacity={main=0,border=.55*visibility}}) end
            if hover and self.tooltip then ass:tooltip(self,ui.text(self.tooltip)) end
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
            ass:icon(cx,cy,self.font_size*0.80,self.icon,{color=color,opacity=visibility,border=0,
                border_color='111111',clip=icon_clip})
            return ass
        end
    end)
    extend('TopBar',function(TopBar)
        local dimensions=TopBar.update_dimensions
        function TopBar:update_dimensions()
            dimensions(self)
            if #(T.metadata.badges or {})>0 then
                self.by=math.max(self.by,self.ay+self.size+self.chapter_size-options.proximity_in)
            end
        end
        function TopBar:render()
            local visibility=self:get_visibility()
            if visibility<=0 then return end
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
            local x,y,limit=ax+margin,ay+margin,bx-margin
            local padding=round(self.font_size/2)
            if state.has_playlist then
                local text=state.playlist_pos..'/'..state.playlist_count
                local width=metrics.width(text,self.font_size,config.font,options.font_bold)+padding*2
                local box={ax=x,ay=y,bx=x+width,by=by-margin}
                T.header(ass,box,visibility,true)
                ass:txt(x+width/2,(box.ay+box.by)/2,5,text,{size=self.font_size,
                    color='ffffff',opacity=visibility})
                cursor:zone('primary_click',box,function() mp.command('script-binding uosc/playlist') end)
                x=box.bx+margin
            end
            local row_x=x
            local function title(text,size,height,toggle)
                if state.is_idle or not text or text=='' or limit-x<size*3 then return end
                local width=math.min(metrics.width(text,size,config.font,options.font_bold)+padding*2,limit-x)
                local box={ax=x,ay=y,bx=x+width,by=y+height}
                T.header(ass,box,visibility)
                ass:txt(x+padding,y+height/2,4,text,{size=size,color='ffffff',border=0,
                    border_color='000000',opacity=visibility,wrap=2,
                    clip=string.format('\\clip(%d,%d,%d,%d)',math.floor(x),math.floor(y),math.floor(box.bx-padding/2),math.ceil(box.by))})
                if toggle then cursor:zone('primary_click',box,function() self:toggle_title() end) end
                y=box.by+3*s
                return box
            end
            if options.top_bar_title~='no' then
                title(self.render_titles.main,self.font_size,self.size-2*margin,options.top_bar_alt_title_place=='toggle')
                if options.top_bar_alt_title_place=='below' then
                    title(self.render_titles.alt,round(self.alt_title_size*0.77),self.alt_title_size)
                end
            else y=by end
            local badges={}
            for _,badge in ipairs(T.metadata.summary or T.metadata.badges or {})do
                if badge.kind~='chapter' and badge.kind~='timer' then badges[#badges+1]=badge end
            end
            -- Metadata remains visible without chapters. Wrap badges in small windows.
            local size=math.max(12*s,round(self.font_size*0.77))
            local height=math.max(self.chapter_size,22*s)
            local available=self.bx-margin-row_x
            if available<170*s then row_x=ax+margin end
            x=row_x
            for _,badge in ipairs(badges) do
                local text=ass_escape(badge.text)
                local icon=({video='local_movies',audio='graphic_eq'})[badge.kind]
                local icon_width=icon and 22*s or 0
                local width=metrics.width(badge.text,size,config.font,options.font_bold)+12*s+icon_width
                width=math.min(width,limit-row_x)
                if x+width>limit and x>row_x then x=row_x;y=y+height+3*s end
                local box={ax=x,ay=y,bx=x+width,by=y+height}
                T.header(ass,box,visibility)
                if icon then ass:icon(x+13*s,y+height/2,18*s,icon,{color='d4d4d4',opacity=visibility,border=0}) end
                ass:txt(x+6*s+icon_width,y+height/2,4,text,{size=size,color='ffffff',border=0,
                    border_color='000000',opacity=visibility,wrap=2,
                    clip=string.format('\\clip(%d,%d,%d,%d)',math.floor(x),math.floor(y),math.floor(box.bx-3*s),math.ceil(box.by))})
                x=box.bx+3*s
            end
            self.title_by=#badges>0 and y+height or y
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
