-- Local rendering and navigation adapters for upstream uosc.
return function(script_directory)
    local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
    package.preload['lib/intl']=function()
        assert(loadfile(script_directory..'/lib/intl.lua'))()
        return {t=function(text,arg)
            if not text then return '' end
            return string.format(ui.text(text),arg or '')
        end}
    end
    mp.observe_property('user-data/interface-language','string',function()
        if request_render then request_render() end
    end)

    mp.observe_property('user-data/skip-segments','native',function()
        if request_render then request_render() end
    end)

    -- Format only menu rows. mpv's playlist and media-title remain untouched.
    package.preload['lib/menus']=function()
        local original=assert(loadfile(script_directory..'/lib/menus.lua'))()
        local create=create_self_updating_menu_opener
        local fmt=dofile(mp.command_native({'expand-path','~~/extensions/title_format.lua'}))
        local anime=dofile(mp.command_native({'expand-path','~~/extensions/anime_identity.lua'}))
        function create_self_updating_menu_opener(opts)
            if opts.type=='sub' then
                local serialize,activate,key=opts.serializer,opts.on_activate,opts.on_key
                opts.active_prop='sid'
                opts.serializer=function(list,...)
                    local rows,selected=serialize(list,...)
                    table.insert(rows,1,{title='Выключить субтитры',icon='subtitles_off',value='{disable}',
                        active=not tonumber(mp.get_property('sid')) and not tonumber(mp.get_property('secondary-sid')),
                        separator=true})
                    return rows,selected and selected+1 or nil
                end
                opts.on_activate=function(event)
                    if event.value=='{disable}' then
                        mp.commandv('script-binding','subtitle_controls/off')
                    else activate(event) end
                end
                opts.on_key=function(event,...)
                    if event.selected_item and event.selected_item.value=='{disable}' then return end
                    if key then return key(event,...) end
                end
            end
            if opts.type=='playlist' then
                opts.actions_place='outside'
                local serialize=opts.serializer
                opts.serializer=function(list,...)
                    local rows,selected=serialize(list,...)
                    local meta=mp.get_property_native('user-data/readable-title',{})
                    local lang=meta.language or 'ru'
                    for _,row in ipairs(rows) do
                        local data=anime.enrich(row.title,fmt.parse(row.title))
                        if data.title~='' or data.episode then
                            local same=meta.source_title and fmt.normalize(data.title)==fmt.normalize(meta.source_title)
                            local ep=same and data.season==meta.season and meta.episodes and meta.episodes[tostring(data.episode)]
                            row.title=fmt.label(data,lang,same and meta.title or nil,ep or nil)
                        end
                    end
                    return rows,selected
                end
                mp.observe_property('user-data/readable-title','native',function()
                    if Menu:is_open('playlist') then
                        Elements:maybe('menu','update_items',opts.serializer(mp.get_property_native('playlist',{})))
                    end
                end)
            end
            return create(opts)
        end
        return original
    end
    local function extend(name, install)
        package.preload['elements/' .. name] = function()
            local original = assert(loadfile(script_directory .. '/elements/' .. name .. '.lua'))()
            install(original)
            return original
        end
    end

    extend('Menu',function(Menu)
        local update=Menu.update
        function Menu:update(data) return update(self,ui.menu(data)) end
    end)
    local controls_always=false
    mp.observe_property('user-data/player-ui/controls-always','bool',function(_,value)
        controls_always=value==true;if request_render then request_render() end
    end)
    extend('Element',function(Element)
        local persistent=Element.is_persistent
        local controls={controls=true,timeline=true,top_bar=true,volume=true,speed=true}
        function Element:is_persistent()
            if controls_always and not state.is_idle and controls[self.id] then return true end
            return persistent(self)
        end
    end)
    local theme=dofile(mp.command_native({'expand-path','~~/extensions/uosc_theme.lua'}))(extend)
    extend('Timeline', function(Timeline)
        dofile(mp.command_native({'expand-path','~~/extensions/network_seek.lua'}))(Timeline)
        function Timeline:rail()
            local s = state.scale
            local opts = {size = self.font_size}
            -- Reserve a fixed digit budget from the file duration, never from the current clock.
            local widest,digit_width='0',0
            for n=0,9 do
                local width=text_width(tostring(n),opts)
                if width>digit_width then widest,digit_width=tostring(n),width end
            end
            local sample=format_time(math.max(5999,state.duration or 0),math.max(5999,state.duration or 0)):gsub('%d',widest)
            local timestamp=text_width('-'..sample,opts)
            -- Keep generous clickable height while drawing a slim rail.
            local pad = math.min(timestamp + 20*s, self.width * 0.28)
            return self.ax + pad, self.bx - pad, self.by - self.size / 2
        end
        function Timeline:get_time_at_x(x)
            local ax, bx = self:rail()
            return (state.duration or 0) * clamp(0, (x - ax) / math.max(1, bx - ax), 1)
        end
        function Timeline:render()
            local visibility = self:get_visibility()
            self.is_hovered = self.proximity_raw <= 0
            if self.size == 0 or visibility <= 0 or not state.duration or not state.time then
                self.is_hovered = false
                self:clear_thumbnail()
                return
            end
            cursor:zone('primary_down', self, function()
                self:handle_cursor_down()
                cursor:once('primary_up', function() self:handle_cursor_up() end)
            end)
            if #options.timeline_mbtn_right > 0 then
                cursor:zone('secondary_down', self, function() self:cursor_command(options.timeline_mbtn_right) end)
            end
            if config.timeline_step ~= 0 then
                cursor:zone('wheel_down', self, function() mp.commandv('seek', -config.timeline_step, config.timeline_step_flag) end)
                cursor:zone('wheel_up', self, function() mp.commandv('seek', config.timeline_step, config.timeline_step_flag) end)
            end
            local ass, s = assdraw.ass_new(), state.scale
            local ax, bx, cy = self:rail()
            local r = 2.5 * s
            local function t2x(t) return ax + (bx - ax) * clamp(0, t / state.duration, 1) end
            local px = t2x(state.time)
            local rail_style=theme.rail_style(visibility);rail_style.radius=r
            ass:rect(ax,cy-r,bx,cy+r,rail_style)
            -- Cached data is a plain translucent line, not a striped panel.
            if options.timeline_cache and state.uncached_ranges then
                local start = 0
                local function cached(a,b)
                    if b > a then ass:rect(t2x(a),cy-r,t2x(b),cy+r,{color='ffffff',opacity=(theme.glass() and 0.36 or 0.22)*visibility,radius=r}) end
                end
                for _, range in ipairs(state.uncached_ranges) do
                    cached(start,range[1]); start=math.max(start,range[2])
                end
                cached(start,state.duration)
            end
            if options.timeline_style == 'bar' and px > ax then
                ass:rect(ax,cy-r,px,cy+r,{color='ffffff',opacity=(theme.glass() and 0.96 or 0.76)*visibility,radius=r})
            end
            local skip=mp.get_property_native('user-data/skip-segments',{})
            local media=(mp.get_property('path') or '')..'|'..tostring(mp.get_property_number('playlist-pos',-1))
            if theme.marks and skip.key==media then
                local points={}
                for _,segment in ipairs(skip.segments or {}) do
                    local a,b=segment.start,segment['end']
                    if a and b and a>=0 and b>a and b<=state.duration+1 then
                        ass:rect(t2x(a),cy-r,t2x(math.min(b,state.duration)),cy+r,
                            {color='FFD79C',opacity=(theme.glass() and 0.95 or 0.8)*visibility,radius=r})
                        for _,time in ipairs({a,b}) do
                            local x=t2x(math.min(time,state.duration))
                            points[#points+1]=x
                        end
                    end
                end
                table.sort(points)
                local last
                for _,x in ipairs(points) do
                    if not last or x-last>=6*s then
                        ass:circle(x,cy,2.2*s,{color='ffffff',border=0.6*s,border_color='303030',opacity=visibility})
                        last=x
                    end
                end
            end
            for _, name in ipairs({'a','b'}) do
                local t=state['ab_loop_'..name]
                if t and t>=0 then
                    ass:txt(t2x(t),cy-7*s,2,name:upper(),{size=12*s,border=s,opacity=visibility})
                end
            end
            ass:rect(px-2.5*s,cy-9*s,px+2.5*s,cy+9*s,{color='ffffff',radius=2.5*s,opacity=visibility})
            local opts={size=self.font_size,color='ffffff',border=0,border_color='000000',opacity=visibility}
            ass:txt(self.ax+10*s,cy,4,state.time_human or '',opts)
            ass:txt(self.bx-10*s,cy,6,state.destination_time_human or '',opts)

            local rendered=false
            if (self.is_hovered or self.pressed) and not Elements:v('speed','dragging') then
                local x=clamp(ax,cursor.x,bx)
                local seconds=self:get_time_at_x(x)
                local anchor={ax=x,ay=self.ay-3*s,bx=x,by=self.ay}
                local human=format_time(seconds,state.duration)
                anchor=ass:tooltip(anchor,human,{size=self.font_size,offset=2*s,margin=2*s,
                    timestamp=options.time_precision>0,width_overwrite=timestamp_width(human,{size=self.font_size})})
                if not thumbnail.disabled and (not self.pressed or self.pressed.distance<5)
                    and thumbnail.width>0 and thumbnail.height>0 then
                    local b=2*s
                    local tx=round(clamp(b+2*s,x-thumbnail.width/2,display.width-thumbnail.width-b-2*s))
                    local ty=round(anchor.ay-b-2*s-thumbnail.height)
                    ass:rect(tx-b,ty-b,tx+thumbnail.width+b,ty+thumbnail.height+b,
                        {color='000000',radius=3*s,opacity=0.6*visibility})
                    local t=(state.rebase_start_time==false and state.start_time) and seconds-state.start_time or seconds
                    mp.commandv('script-message-to','thumbfast','thumb',t,tx,ty)
                    self.has_thumbnail,rendered=true,true
                    anchor.ay=ty-b
                end
                local _,chapter=itable_find(state.chapters,function(c) return seconds>=c.time end,#state.chapters,1)
                if chapter and not chapter.is_end_only then
                    ass:tooltip(anchor,ui.chapter_text(chapter.title_wrapped),{size=self.font_size,offset=2*s,responsive=false,
                        width_overwrite=chapter.title_wrapped_width*self.font_size,lines=chapter.title_lines,margin=2*s})
                end
            end
            if not rendered then self:clear_thumbnail() end
            return ass
        end
    end)

    extend('Speed', function(Speed)
        function Speed:render()
            local opacity=self.dragging and 1 or self:get_visibility()
            if opacity<=0 then return end
            local s=state.scale
            local text=(round(state.speed*100)/100)..'×'
            local size=17*s*options.font_scale
            local cx,cy=(self.ax+self.bx)/2,(self.ay+self.by)/2
            local width=math.max(76*s,text_width(text,{size=size})+22*s)
            local height=34*s
            local box={ax=cx-width/2,ay=cy-height/2,bx=cx+width/2,by=cy+height/2}
            cursor:zone('primary_down',box,function()
                self:handle_cursor_down()
                cursor:once('primary_up',function() self:handle_cursor_up() end)
            end)
            cursor:zone('secondary_click',box,function() mp.set_property_native('speed',1) end)
            cursor:zone('wheel_down',box,function() self:handle_wheel_down() end)
            cursor:zone('wheel_up',box,function() self:handle_wheel_up() end)
            local ass=assdraw.ass_new()
            theme.panel(ass,box,opacity,height/2)
            ass:txt(cx,cy-4*s,5,text,{size=size,color='ffffff',border=0,border_color='000000',opacity=opacity})
            for i=-3,3 do
                local x=cx+i*7*s
                local height=(i==0 and 5 or math.abs(i)==2 and 4 or 2.5)*s
                ass:rect(x-0.5*s,cy+10*s-height,x+0.5*s,cy+10*s,{color='ffffff',opacity=(i==0 and 1 or 0.55)*opacity})
            end
            if get_point_to_rectangle_proximity(cursor,box)<=0 and not self.dragging then
                ass:tooltip(box,ui.text('Скорость (Колесо мыши)'))
            end
            return ass
        end
    end)

    extend('Volume', function(Volume)
        local init=Volume.init
        function Volume:init(...)
            init(self,...)
            assert(self.slider and self.slider.set_from_cursor,'uosc Volume API changed')
            self.slider.render=function(slider)
                local visibility=slider:get_visibility()
                if visibility<=0 or slider.by<=slider.ay then return end
                cursor:zone('primary_down',slider,function()
                    slider.pressed=true;slider:set_from_cursor()
                    cursor:once('primary_up',function() slider.pressed=false end)
                end)
                cursor:zone('wheel_down',slider,function() slider:handle_wheel_down() end)
                cursor:zone('wheel_up',slider,function() slider:handle_wheel_up() end)
                local ass,s=assdraw.ass_new(),state.scale
                local x=(slider.ax+slider.bx)/2
                local r=3*s
                local y=slider.by-(slider.by-slider.ay)*clamp(0,state.volume/state.volume_max,1)
                local rail_style=theme.rail_style(visibility);rail_style.radius=r
                ass:rect(x-r,slider.ay,x+r,slider.by,rail_style)
                if y<slider.by then ass:rect(x-r,y,x+r,slider.by,{color='ffffff',radius=r,opacity=(theme.glass() and 0.96 or 0.76)*visibility}) end
                ass:rect(x-7*s,y-2*s,x+7*s,y+2*s,{color='ffffff',radius=2*s,opacity=visibility})
                ass:txt(x,slider.ay-8*s,2,tostring(round(state.volume)),{size=16*s,color='ffffff',
                    border=0,border_color='000000',opacity=visibility})
                return ass
            end
        end
        local render=Volume.render
        function Volume:render()
            local original=render(self)
            if not original or not theme.glass() then return original end
            local ass=assdraw.ass_new()
            theme.panel(ass,{ax=self.ax,ay=self.mute_ay,bx=self.bx,by=self.by},self:get_visibility(),self.size/2)
            ass.text=ass.text..original.text
            return ass
        end
    end)
end
