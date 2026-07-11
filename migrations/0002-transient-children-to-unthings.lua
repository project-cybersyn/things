for id, thing in pairs(storage.things) do
	local transient_children = thing.transient_children
	if transient_children then
		thing.children = thing.children or {}
		local thing_children = thing.children
		for index, transient_child in pairs(transient_children) do
			index = tostring(index)
			if not thing_children[index] then
				local chun = create_unthing_child(transient_child, thing, index)
				if chun then
					thing_children[index] = { chun }
					log(
						string.format(
							"MIGRATION: Thing ID %s has a transient child at index %s -- the transient child was converted to a proper child.",
							id,
							index
						)
					)
				else
					log(
						string.format(
							"MIGRATION FAILURE: Thing ID %s has a transient child at index %s -- the transient child could not be converted to a proper child and is being discarded.",
							id,
							index
						)
					)
					if transient_child.valid then transient_child.destroy() end
				end
			else
				log(
					string.format(
						"MIGRATION FAILURE: Thing ID %s has both a child and a transient at index %s -- the transient child is being discarded.",
						id,
						index
					)
				)
				if transient_child.valid then transient_child.destroy() end
			end
		end

		thing.transient_children = nil
	end
end
