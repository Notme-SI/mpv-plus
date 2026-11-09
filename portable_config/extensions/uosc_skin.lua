-- Local rendering and navigation adapters for upstream uosc.
return function(script_directory)
    local clock=dofile(mp.command_native({'expand-path','~~/'})..'/extensions/time_format.lua').clock
    local ui=dofile(mp.command_native({'expand-path','~~/extensions/ui_locale.lua'}))
    local root=mp.command_native({'expand-path','~~/'})
    local glyphs=dofile(root..'/extensions/lucide_glyphs.lua')
    local surface=dofile(root..'/extensions/glass_surface.lua')
    local preset='menu,command:cloud:script-binding torrserver_loader/torr_open?TorrServer,playlist,space,speed:0.9,space,audio,subtitles,button:theintrodb,cycle:pin_off:ontop:no/yes=push_pin!?Поверх всех окон,fullscreen'
    local previous=preset:gsub('cycle:pin_off:ontop:no/yes=push_pin!', 'cycle:window_normal:ontop:no/yes=window_on_top!')
    local legacy='play-pause?Пауза/Воспроизвести,menu,command:cloud:script-binding torrserver_loader/torr_open?TorrServer,subtitles,audio,button:theintrodb,space,speed:0.9,space,prev,playlist,next,toggle:push_pin:ontop?Поверх всех окон,fullscreen'
    local function player_layout() return options.controls==preset or options.controls==previous or options.controls==legacy end
    local function controls_height() return round((options.controls_size+2)*state.scale) end
    package.preload['lib/utils']=function()
        local original=assert(loadfile(script_directory..'/lib/utils.lua'))()
        local format_key=keybind_to_human
        local upper={}
        local letters='АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
        local i=0
        for letter in ('абвгдеёжзийклмнопрстуфхцчшщъыьэюя'):gmatch('[\208\209][\128-\191]') do
            upper[letter]=letters:sub(i+1,i+2)
            i=i+2
        end
        function keybind_to_human(key)
            return (format_key(key):upper():gsub('[\208\209][\128-\191]',upper))
        end
        return original
    end
    -- Weak aliases also cover older installations whose input.conf is preserved.
    for _,alias in ipairs({{'Ctrl+з','Ctrl+p'},{'Alt+з','Alt+p'},{'Ctrl+е','Ctrl+t'},{'а','f'},{'С','C'}}) do
        local translated,original=alias[1],alias[2]
        mp.add_key_binding(translated,'layout-'..original,function() mp.commandv('keypress',original) end)
    end
    package.preload['lib/ass']=function()
        local original=assert(loadfile(script_directory..'/lib/ass.lua'))()
        local methods=getmetatable(assdraw.ass_new())
        local icon=methods.icon
        function methods:icon(x,y,size,name,opts)
            if name=='subtitles' then
                opts=opts or {}
                return surface.caption(self,x,y,size,opts.color or 'ffffff',opts.opacity or 1,opts.clip)
            end
            if not glyphs[name] then return icon(self,x,y,size,name,opts) end
            opts=opts or {}
            opts.font,opts.size,opts.bold='lucide',size,false
            self:txt(x,y,opts.align or 5,glyphs[name],opts)
        end
        return original
    end
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
        local lampa=dofile(mp.command_native({'expand-path','~~/extensions/lampa_context.lua'}))
        local source=dofile(mp.command_native({'expand-path','~~/extensions/media_source.lua'}))
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
                opts.actions_place='inside'
                opts.footnote=nil
                local serialize=opts.serializer
                opts.serializer=function(list,...)
                    local rows,selected=serialize(list,...)
                    local meta=mp.get_property_native('user-data/readable-title',{})
                    local lang=meta.language or 'ru'
                    for index,row in ipairs(rows) do
                        local entry=list[tonumber(row.value) or 0]
                        local data=entry and lampa.current(row.title,entry.filename)
                        data=data or anime.from_source(row.title,source.current(entry and entry.filename))
                        if data.title~='' or data.episode then
                            local same=meta.source_title and fmt.normalize(data.title)==fmt.normalize(meta.source_title)
                            if meta.tmdb_id and data.tmdb_id then
                                same=tonumber(meta.tmdb_id)==tonumber(data.tmdb_id)
                                    and (data.tmdb_season or data.season)==(meta.tmdb_season or meta.season)
                                    and (data.tmdb_offset or 0)==(meta.tmdb_offset or 0)
                            end
                            local ep=same and data.season==meta.season and meta.episodes and meta.episodes[tostring(data.episode)]
                            if same then data.season=meta.season;ep=meta.episodes and meta.episodes[tostring(data.episode)] end
                            if same and data.episode then
                                local label=(lang=='en' and 'Episode ' or 'Серия ')..data.episode
                                row.title=ep and ep~='' and (label..' · '..ep) or label
                            else
                                row.title=fmt.label(data,lang,same and meta.title or nil,ep or nil)
                            end
                        end
                        row.hint=row.active and (lang=='en' and 'Playing' or 'Сейчас') or string.format('%02d',index)
                        if row.active then row.icon='play_arrow';row.bold=true end
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

    local menu_theme
    extend('Menu',function(Menu)
        local update=Menu.update
        local dimensions=Menu.update_dimensions
        local coordinates=Menu.update_coordinates
        function Menu:update(data) return update(self,ui.menu(data)) end
        function Menu:update_dimensions()
            if self.type=='playlist' then
                for _,menu in ipairs(self.all) do menu.max_width=math.min(menu.max_width,410*state.scale) end
            end
            return dimensions(self)
        end
        function Menu:update_coordinates()
            if self.type~='playlist' then return coordinates(self) end
            local width=self.current.width+self.padding*2
            local x=math.max(0,display.width-width-math.max(14*state.scale,self.padding))
            self:set_coordinates(x,self.current.top-self.padding,x+width,self.current.top+self.current.height+self.padding)
        end
        if menu_theme then menu_theme.menu(Menu) end
    end)
    extend('Curtain',function(Curtain)
        local render=Curtain.render
        function Curtain:render()
            if not Elements.menu or Elements.menu.type~='playlist' then return render(self) end
            local ass=assdraw.ass_new()
            ass:rect(0,0,display.width,display.height,{color='000000',opacity=.32*self.opacity})
            return ass
        end
    end)
    local controls_always=false
    mp.observe_property('user-data/player-ui/controls-always','bool',function(_,value)
        controls_always=value==true
        if Elements and Elements.timeline then Elements.timeline:decide_enabled() end
        if request_render then request_render() end
    end)
    extend('Element',function(Element)
        local persistent=Element.is_persistent
        local controls={controls=true,timeline=true,speed=true}
        function Element:is_persistent()
            if controls_always and (controls[self.id] or self.anchor_id=='controls') then return true end
            return persistent(self)
        end
    end)
    local theme
    extend('Controls',function(Controls)
        local init_options=Controls.init_options
        local dimensions=Controls.update_dimensions
        function Controls:init_options()
            self.player_layout=player_layout()
            if self.player_layout then options.controls=preset end
            init_options(self)
        end
        function Controls:update_dimensions()
            dimensions(self)
            if not self.player_layout or not self.enabled then return end
            local size=controls_height()
            local gap=math.max(2,round(4*state.scale))
            local margin=round(options.controls_margin*state.scale)
            local border=Elements:v('window_border','size',0)
            self.by=display.height-border-margin
            self.ay=self.by-size
            local center=(self.ax+self.bx)/2
            local half=(self.bx-self.ax)/2
            local speed_width=math.min(size*2.5,math.max(size,half-gap)*2)
            local function place(index,x,width,height,visible)
                local button=self.controls[index].element
                button.enabled=visible and not button.hide
                if button.enabled then
                    local y=(self.ay+self.by-height)/2
                    button:set_coordinates(x,y,x+width,y+height)
                end
            end
            place(5,center-speed_width/2,speed_width,size*.85,half>=size/2)
            local left,right=self.ax,self.bx
            local timeline=Elements.timeline
            if timeline and timeline.width then
                local rail_left,rail_right=timeline:rail()
                local left_clock,right_clock=timeline:clock_centers(rail_left,rail_right)
                left=math.max(left,left_clock-size/2)
                right=math.min(right,right_clock+size/2)
            end
            local room=half-speed_width/2-gap
            for _,index in ipairs({1,2,3}) do
                local visible=left-self.ax+size<=room
                place(index,left,size,size,visible)
                if visible then left=left+size+gap end
            end
            for _,index in ipairs({11,10,9,8,7}) do
                local visible=self.bx-right+size<=room and not self.controls[index].element.hide
                place(index,right-size,size,size,visible)
                if visible then right=right-size-gap end
            end
            Elements:update_proximities()
        end
        function Controls:on_prop_duration()
            if self.player_layout then self:update_dimensions() end
        end
        local visibility=Controls.get_visibility
        function Controls:get_visibility()
            local base=require('elements/Element').get_visibility
            if self.player_layout then
                local own=base(self)
                if Elements.curtain.opacity>0 then return own end
                local timeline=Elements.timeline
                if Elements:v('speed','dragging') or timeline and timeline.pressed then return 1 end
                return math.max(own,timeline and timeline.enabled and base(timeline) or 0)
            end
            if controls_always then return base(self) end
            return visibility(self)
        end
    end)
    theme=dofile(root..'/extensions/uosc_theme.lua')(extend)
    menu_theme=theme
    extend('PauseIndicator',function(PauseIndicator)
        local seeking=false
        mp.observe_property('seeking','bool',function(_,value) seeking=value==true;request_render() end)
        function PauseIndicator:decide()
            request_render()
            -- mpv can skip the first OSD update when pausing on Windows.
            mp.add_timeout(.05,function() osd:update() end)
        end
        PauseIndicator.on_prop_pause=PauseIndicator.decide
        PauseIndicator.flash=PauseIndicator.decide
        function PauseIndicator:render()
            if state.is_idle or not state.is_video or state.core_idle and not state.pause or seeking
                or state.cache_underrun or state.cache_buffering and state.cache_buffering<100
                or Elements:v('timeline','pressed') or Elements.curtain.opacity>0 then return end
            local s=state.scale
            local radius=math.min(30*s,math.min(display.width,display.height)*.09)
            if radius<=0 then return end
            local x,y=display.width/2,display.height/2
            local step=radius*1.95
            local navigation=state.has_playlist and x>step+radius
            local span=navigation and step+radius or radius
            local region={ax=x-span,ay=y-radius,bx=x+span,by=y+radius}
            if not state.pause and get_point_to_rectangle_proximity(cursor,region)>0 then return end
            local ass=assdraw.ass_new()
            local function button(cx,r,icon,command,primary)
                local box={ax=cx-r,ay=y-r,bx=cx+r,by=y+r}
                local hover=command and get_point_to_rectangle_proximity(cursor,box)<=0
                if command then cursor:zone('primary_click',box,command) end
                local opacity=not command and .35 or hover and 1 or .92
                local background=r*.90
                theme.panel(ass,{ax=cx-background,ay=y-background,bx=cx+background,by=y+background},opacity,background,hover,true)
                theme.transport(ass,cx,y,r,icon,opacity)
            end
            if navigation then
                button(x-step,radius*.7,'arrow_back_ios',state.playlist_pos>1 and function()mp.commandv('playlist-prev','weak')end)
                button(x+step,radius*.7,'arrow_forward_ios',state.playlist_pos<state.playlist_count and function()mp.commandv('playlist-next','weak')end)
            end
            button(x,radius,state.pause and 'play_arrow' or 'pause',function()mp.commandv('cycle','pause')end,true)
            return ass
        end
    end)
    extend('BufferingIndicator',function(BufferingIndicator)
        function BufferingIndicator:render()
            local ass,s=assdraw.ass_new(),state.scale
            local x,y=display.width/2,display.height/2
            local radius=math.min(19*s,display.width*.08,math.max(12,display.height*.025))
            if radius<=0 then return end
            local visibility=Elements.curtain.opacity>0 and .42 or .95
            local box={ax=x-radius,ay=y-radius,bx=x+radius,by=y+radius}
            local background=radius*.90
            theme.panel(ass,{ax=x-background,ay=y-background,bx=x+background,by=y+background},visibility,background,false)
            ass:icon(x,y,radius*1.35,'loader',{color='ffffff',opacity=visibility,rotate=-(mp.get_time()*210)%360})
            request_render()
            return ass
        end
    end)
    extend('Timeline', function(Timeline)
        dofile(mp.command_native({'expand-path','~~/extensions/network_seek.lua'}))(Timeline)
        local dimensions=Timeline.update_dimensions
        function Timeline:update_dimensions()
            dimensions(self)
            if player_layout() and display.height>=120*state.scale then
                local lift=controls_height()+round((options.controls_margin+5)*state.scale)
                self.ay,self.by=self.ay-lift,self.by-lift
            end
        end
        local visibility=Timeline.get_visibility
        function Timeline:get_visibility()
            if Elements:v('controls','player_layout') and Elements:v('controls','enabled') then
                return Elements.controls:get_visibility()
            end
            return visibility(self)
        end
        local decide_enabled=Timeline.decide_enabled
        function Timeline:decide_enabled()
            if controls_always and state.is_idle and not self.obstructed then
                local previous=self.enabled
                self.enabled=true
                if not previous then Elements:trigger('timeline_enabled',true) end
            else decide_enabled(self) end
        end
        function Timeline:on_prop_is_idle() self:decide_enabled() end
        function Timeline:rail()
            local s = state.scale
            local opts = {size = self.font_size*.84}
            -- Reserve a fixed digit budget from the file duration, never from the current clock.
            local widest,digit_width='0',0
            for n=0,9 do
                local width=text_width(tostring(n),opts)
                if width>digit_width then widest,digit_width=tostring(n),width end
            end
            local sample=clock(format_time(math.max(5999,state.duration or 0),math.max(5999,state.duration or 0))):gsub('%d',widest)
            local timestamp=text_width(sample,opts)
            -- Keep generous clickable height while drawing a slim rail.
            local pad = math.min(timestamp + 24*s, self.width * 0.28)
            return self.ax + pad, self.bx - pad, self.by - self.size / 2
        end
        function Timeline:clock_centers(rail_left,rail_right)
            return (self.ax+rail_left)/2,(rail_right+self.bx)/2
        end
        function Timeline:draw_clocks(ass,ax,bx,y,left,right,opacity)
            local s,size=state.scale,self.font_size*.84
            local function clock_chip(x,gutter,label)
                local text_size=text_width(label,{size=size})
                local width=math.min(gutter-4*s,text_size+13*s)
                if width<text_size then return end
                local radius=(size+6*s)/2
                theme.panel(ass,{ax=x-width/2,ay=y-radius,bx=x+width/2,by=y+radius},opacity,radius)
                ass:txt(x,y,5,label,{size=size,color='ffffff',opacity=opacity})
            end
            local left_x,right_x=self:clock_centers(ax,bx)
            clock_chip(left_x,ax-self.ax,left)
            clock_chip(right_x,self.bx-bx,right)
        end
        function Timeline:get_time_at_x(x)
            local ax, bx = self:rail()
            return (state.duration or 0) * clamp(0, (x - ax) / math.max(1, bx - ax), 1)
        end
        function Timeline:render()
            local visibility = self:get_visibility()
            self.is_hovered = self.proximity_raw <= 0
            if controls_always and state.is_idle and self.size>0 and visibility>0 then
                self.is_hovered=false;self:clear_thumbnail()
                local ass,s=assdraw.ass_new(),state.scale
                local ax,bx,cy=self:rail()
                local style=theme.rail_style(visibility*0.45);style.radius=2.5*s
                ass:rect(ax,cy-2.5*s,bx,cy+2.5*s,style)
                self:draw_clocks(ass,ax,bx,cy,'00:00','00:00',visibility*.45)
                -- No seek handlers until a file with a duration is loaded.
                return ass
            end
            if self.size == 0 or visibility <= 0 or not state.duration or state.duration<=0 or not state.time then
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
                    if segment.kind~='preview' and a and b and a>=0 and b>a and b<=state.duration+1 then
                        ass:rect(t2x(a),cy-r,t2x(math.min(b,state.duration)),cy+r,
                            {color=theme.mark_color,opacity=visibility,radius=r})
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
                        ass:circle(x,cy,2.2*s,{color=theme.mark_color,border=0.6*s,border_color='303030',opacity=visibility})
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
            self:draw_clocks(ass,ax,bx,cy,clock(state.time_human),clock(state.destination_time_human),visibility)

            local rendered=false
            if (self.is_hovered or self.pressed) and not Elements:v('speed','dragging') then
                local x=clamp(ax,cursor.x,bx)
                local seconds=self:get_time_at_x(x)
                local anchor={ax=x,ay=self.ay-3*s,bx=x,by=self.ay}
                local human=clock(format_time(seconds,state.duration))
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
        local visibility=Speed.get_visibility
        function Speed:get_visibility()
            if self.anchor_id=='controls' and Elements:v('controls','player_layout') then return Elements.controls:get_visibility() end
            if controls_always then return require('elements/Element').get_visibility(self) end
            return visibility(self)
        end
        function Speed:render()
            local opacity=self.dragging and 1 or self:get_visibility()
            if opacity<=0 then return end
            local s=state.scale
            local text=(round(state.speed*100)/100)..'×'
            local size=17*s*options.font_scale
            local cx,cy=(self.ax+self.bx)/2,(self.ay+self.by)/2
            local width=math.max(68*s,text_width(text,{size=size})+18*s)
            local height=math.min(28*s,self.by-self.ay)
            local box={ax=cx-width/2,ay=cy-height/2,bx=cx+width/2,by=cy+height/2}
            cursor:zone('primary_down',box,function()
                self:handle_cursor_down()
                cursor:once('primary_up',function() self:handle_cursor_up() end)
            end)
            cursor:zone('secondary_click',box,function() mp.set_property_native('speed',1) end)
            cursor:zone('wheel_down',box,function() self:handle_wheel_down() end)
            cursor:zone('wheel_up',box,function() self:handle_wheel_up() end)
            local ass=assdraw.ass_new()
            local hover=get_point_to_rectangle_proximity(cursor,box)<=0
            local grouped=self.anchor_id=='controls' and Elements:v('controls','player_layout')
            theme.panel(ass,box,opacity,height/2,hover)
            ass:txt(cx,cy-4*s,5,text,{size=size,color='ffffff',border=0,border_color='000000',opacity=opacity})
            for i=-3,3 do
                local x=cx+i*7*s
                local height=(i==0 and 5 or math.abs(i)==2 and 4 or 2.5)*s
                ass:rect(x-0.5*s,cy+10*s-height,x+0.5*s,cy+10*s,{color='ffffff',opacity=(i==0 and 1 or 0.55)*opacity})
            end
            if hover and not self.dragging then
                theme.tooltip(ass,box,ui.text('Скорость'),ui.language()=='en' and 'Scroll' or 'Скролл',opacity,grouped)
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
            -- A separate ASS stream starts with its own first event. Without a
            -- separator, the panel's (0,0) position also moves the speaker icon.
            ass:new_event()
            ass.text=ass.text..original.text
            return ass
        end
    end)
end
