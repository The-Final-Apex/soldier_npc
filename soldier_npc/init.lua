-- soldier_npc/init.lua

-- Register teams: Red, Blue, Green
local teams = {"red", "blue", "green"}
local soldiers = {}

-- Function to create a soldier NPC
local function register_soldier(team)
    minetest.register_entity("soldier_npc:" .. team .. "_soldier", {
        initial_properties = {
            physical = true,  -- Enables collision and gravity
            collide_with_objects = true,
            collisionbox = {-0.35, 0, -0.35, 0.35, 1.8, 0.35},
            visual = "mesh",
            mesh = "character.b3d",
            textures = {"character_" .. team .. ".png"}, -- Different textures for each team
            visual_size = {x = 1, y = 1},
            makes_footstep_sound = true,
            automatic_rotate = false,
            pointable = true, -- Make soldier appear on minimap radar
        },

        -- Soldier properties
        team = team,
        hp = 20,
        damage = 5,
        view_range = 20,
        attack_cooldown = 2,  -- Time between attacks
        timer = 0,
        wielded_weapon = "guns4d_pack_1:m4",
        state = "patrolling",
        patrol_timer = 0,
        paused = false,
        animation = {
            speed_normal = 30,
            speed_run = 60,
            stand_start = 0,
            stand_end = 79,
            walk_start = 168,
            walk_end = 187,
            shoot_start = 200,
            shoot_end = 219,
        },

        -- Function to handle soldier behavior
        on_activate = function(self)
            self.object:set_animation(
                {x = self.animation.stand_start, y = self.animation.stand_end},
                self.animation.speed_normal,
                0
            )
            self.object:set_wielded_item(self.wielded_weapon) -- Make NPC wield the weapon
            table.insert(soldiers, self)
        end,

        on_step = function(self, dtime)
            if self.paused then
                self.object:set_velocity({x = 0, y = 0, z = 0})
                return
            end

            local pos = self.object:get_pos()
            if not pos then return end

            self.timer = self.timer + dtime
            self.patrol_timer = self.patrol_timer + dtime

            -- Apply gravity to the entity
            local velocity = self.object:get_velocity()
            if velocity then
                if minetest.get_node(vector.add(pos, {x = 0, y = -1, z = 0})).name == "air" then
                    velocity.y = velocity.y - 9.8 * dtime
                    self.object:set_velocity(velocity)
                end
            end

            -- Patrolling behavior
            if self.state == "patrolling" then
                if self.patrol_timer > 5 then
                    self.patrol_timer = 0
                    local new_pos = vector.add(pos, {x = math.random(-10, 10), y = 0, z = math.random(-10, 10)})
                    self.object:set_velocity(vector.multiply(vector.direction(pos, new_pos), 1))
                    self.object:set_animation(
                        {x = self.animation.walk_start, y = self.animation.walk_end},
                        self.animation.speed_normal,
                        0
                    )
                end

                -- Look for nearby entities to switch to attack state
                local objs = minetest.get_objects_inside_radius(pos, self.view_range)
                for _, obj in pairs(objs) do
                    if obj:is_player() or obj:get_luaentity() then
                        local lua_entity = obj:get_luaentity()
                        if obj:is_player() or (lua_entity and lua_entity.team and lua_entity.team ~= self.team) then
                            self.state = "attacking"
                            self.target = obj
                            break
                        end
                    end
                end

            -- Attacking behavior
            elseif self.state == "attacking" then
                if self.target and self.target:get_pos() then
                    local target_pos = self.target:get_pos()
                    local direction = vector.direction(pos, target_pos)
                    local distance = vector.distance(pos, target_pos)

                    -- Face the target
                    self.object:set_yaw(minetest.dir_to_yaw(direction))

                    -- Move towards or evade the target
                    if distance > 10 then
                        self.object:set_velocity(vector.multiply(direction, 2)) -- Move towards the target
                        self.object:set_animation(
                            {x = self.animation.walk_start, y = self.animation.walk_end},
                            self.animation.speed_run,
                            0
                        )
                    elseif distance < 5 then
                        -- Strafe sideways
                        local strafe_direction = {x = -direction.z, y = 0, z = direction.x}
                        if math.random() > 0.5 then
                            strafe_direction = vector.multiply(strafe_direction, -1)
                        end
                        self.object:set_velocity(vector.multiply(strafe_direction, 2))
                        self.object:set_animation(
                            {x = self.animation.walk_start, y = self.animation.walk_end},
                            self.animation.speed_run,
                            0
                        )
                    else
                        self.object:set_velocity({x = 0, y = 0, z = 0}) -- Stop to shoot
                        self.object:set_animation(
                            {x = self.animation.shoot_start, y = self.animation.shoot_end},
                            self.animation.speed_normal,
                            0
                        )
                    end

                    -- Shoot the target if within attack range
                    if self.timer >= self.attack_cooldown then
                        self.timer = 0
                        if distance <= self.view_range then
                            local accuracy = math.random()
                            if accuracy <= 0.75 then -- 75% accuracy
                                minetest.sound_play("gun_shot", {pos = pos, gain = 1.0, max_hear_distance = 50})
                                self.target:punch(self.object, 1.0, {
                                    full_punch_interval = 1.0,
                                    damage_groups = {fleshy = self.damage},
                                }, direction)
                            end
                        end
                    end

                    -- Lose target if it moves out of range
                    if distance > self.view_range then
                        self.state = "patrolling"
                        self.target = nil
                        self.object:set_animation(
                            {x = self.animation.stand_start, y = self.animation.stand_end},
                            self.animation.speed_normal,
                            0
                        )
                    end
                else
                    -- Return to patrolling if the target is invalid
                    self.state = "patrolling"
                    self.target = nil
                    self.object:set_animation(
                        {x = self.animation.stand_start, y = self.animation.stand_end},
                        self.animation.speed_normal,
                        0
                    )
                end
            end
        end,
    })
end

-- Register soldiers for each team
for _, team in ipairs(teams) do
    register_soldier(team)
end

-- Command to spawn soldiers
minetest.register_chatcommand("spawn_soldier", {
    params = "<team>",
    description = "Spawn a soldier from the specified team (red, blue, green)",
    func = function(name, param)
        if param ~= "red" and param ~= "blue" and param ~= "green" then
            return false, "Invalid team. Use red, blue, or green."
        end

        local player = minetest.get_player_by_name(name)
        if player then
            local pos = player:get_pos()
            pos.y = pos.y + 1
            minetest.add_entity(pos, "soldier_npc:" .. param .. "_soldier")
            return true, "Spawned a " .. param .. " soldier."
        end
        return false, "Player not found."
    end,
})

-- Command to spawn soldiers in mass
minetest.register_chatcommand("mass_spawn_soldiers", {
    params = "<team> <count>",
    description = "Spawn multiple soldiers from the specified team (red, blue, green)",
    func = function(name, param)
        local team, count = param:match("^(%w+)%s+(%d+)$")
        count = tonumber(count)

        if not team or (team ~= "red" and team ~= "blue" and team ~= "green") or not count then
            return false, "Invalid parameters. Use: <team> <count> (e.g., red 10)"
        end

        local player = minetest.get_player_by_name(name)
        if player then
            local pos = player:get_pos()
            for i = 1, count do
                local spawn_pos = vector.add(pos, {x = math.random(-5, 5), y = 0, z = math.random(-5, 5)})
                minetest.add_entity(spawn_pos, "soldier_npc:" .. team .. "_soldier")
            end
            return true, "Spawned " .. count .. " " .. team .. " soldiers."
        end
        return false, "Player not found."
    end,
})

-- Command to pause all soldiers
minetest.register_chatcommand("pause_soldiers", {
    description = "Pause all soldier NPCs",
    func = function()
        for _, soldier in ipairs(soldiers) do
            soldier.paused = true
            soldier.object:set_velocity({x = 0, y = 0, z = 0})
            soldier.object:set_animation(
                {x = soldier.animation.stand_start, y = soldier.animation.stand_end},
                soldier.animation.speed_normal,
                0
            )
        end
        return true, "All soldiers have been paused."
    end,
})

-- Command to resume all soldiers
minetest.register_chatcommand("resume_soldiers", {
    description = "Resume all soldier NPCs",
    func = function()
        for _, soldier in ipairs(soldiers) do
            soldier.paused = false
        end
        return true, "All soldiers have been resumed."
    end,
})



