local reg_items = minetest.registered_items

local revealed_cache = {}

minetest.register_on_leaveplayer(function(player)
	revealed_cache[player:get_player_name()] = nil
end)

local function item_has_groups(item_groups, groups)
	for i = 1, #groups do
		local group = groups[i]
		if not item_groups[group] then
			return
		end
	end
	return true
end

local function revealed_show_recipe(recipe, playername)
	if not revealed_cache[playername] then
		revealed_cache[playername] = {}
	end
	if revealed_cache[playername][recipe] then
		return true
	end

	local revealed = doc.data.players[playername].stored_data.revealed
	for _, item in pairs(recipe.items) do
		local is_revealed_item = false
		if item:sub(1,6) == "group:" then
			local groups = item:sub(7):split(",")
			for cid, items in pairs(revealed) do
				for revealed_item in pairs(items) do
					if reg_items[revealed_item] and item_has_groups(reg_items[revealed_item].groups, groups) then
						is_revealed_item = true
						break
					end
				end
				if is_revealed_item then
					break
				end
			end
		else
			for cid, items in pairs(revealed) do
				if items[item] then
					is_revealed_item = true
					break
				end
			end
		end

		if not is_revealed_item then
			return false
		end
	end
	revealed_cache[playername][recipe] = true
	return true
end

if minetest.get_modpath("craftguide") then
	craftguide.remove_recipe_filter("Default progressive filter")
	craftguide.add_recipe_filter('reveal', function(recipes, player)
		if not recipes then
			return
		end
		local filtered = {}
		for i = 1, #recipes do
			local recipe = recipes[i]
			if revealed_show_recipe(recipe, player:get_player_name()) then
				filtered[#filtered + 1] = recipe
			end
		end
		return filtered
	end)
end

if minetest.get_modpath("mtg_craftguide") then
	if not (minetest.global_exists("mtg_craftguide") and mtg_craftguide.execute_search) then
		minetest.log("warning", "[craftguide_reveal] mtg_craftguide fork not supported" )
		minetest.log("warning", "[craftguide_reveal] Please use the enhanced fork by bell07" )
		return
	end

	local orig_execute_search = mtg_craftguide.execute_search
	local orig_get_usages = mtg_craftguide.get_usages
	local orig_get_recipes = mtg_craftguide.get_recipes
	local orig_mark_entry_as_revealed = doc.mark_entry_as_revealed

	function mtg_craftguide.get_usages(data, item)
		local recipes = orig_get_usages(data, item)
		if not recipes then
			return
		end

		local filtered = {}
		for _, recipe in ipairs(recipes) do
			if revealed_show_recipe(recipe, data.playername) then
				table.insert(filtered, recipe)
			end
		end
		if #filtered > 0 then
			return filtered
		end
	end

	function mtg_craftguide.get_recipes(data, item)
		local recipes = orig_get_recipes(data, item)
		if not recipes then
			return
		end

		local filtered = {}
		for _, recipe in ipairs(recipes) do
			if revealed_show_recipe(recipe, data.playername) then
				table.insert(filtered, recipe)
			end
		end
		if #filtered > 0 then
			return filtered
		end
	end

	function mtg_craftguide.execute_search(data)
		if not doc.data.players[data.playername] then
			-- Hack. craftguide is loaded before doc mod. Therefore doc is not initialized yet
			data.items = {}
			minetest.after(0, mtg_craftguide.execute_search, data)
			return
		end

		orig_execute_search(data)

		local filtered_items = {}
		for _, item in ipairs(data.items) do
			if mtg_craftguide.get_usages(data, item) or
					mtg_craftguide.get_recipes(data, item) then
				table.insert(filtered_items, item)
			end
		end
		data.items = filtered_items
	end

	-- Update sfinv inventory once in globalstep, if something revealed
	local async_update_users = {}
	local function async_update()
		for playername, _ in pairs(async_update_users) do
			mtg_craftguide.update_for_player(playername)
			async_update_users[playername] = nil
		end
	end

	function doc.mark_entry_as_revealed(playername, category_id, entry_id)
		if not doc.entry_revealed(playername, category_id, entry_id) then
			orig_mark_entry_as_revealed(playername, category_id, entry_id)
			if not next(async_update_users) then
				minetest.after(0, async_update)
				async_update_users[playername] = true
			end
		end
	end
end
