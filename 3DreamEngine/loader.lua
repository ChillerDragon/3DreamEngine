--[[
#part of the 3DreamEngine by Luke100000
#see init.lua for license and documentation
loader.lua - loads .obj files, loads vertex lists
--]]

local lib = _3DreamEngine

function lib.loadObject(self, name, splitMargin)
	local obj = {objects = splitMargin and { } or nil}
	
	--store vertices, normals and texture coordinates
	local vertices = { }
	local normals = { }
	local texVertices = { }
	
	--store final vertices (vertex, normal and texCoord index)
	obj.final = { }
	
	--store final faces, 3 final indices
	obj.faces = { }
	
	--materials
	local materials = { }
	local mat
	for l in love.filesystem.lines(self.objectDir .. name .. ".mtl") do
		local v = self:split(l, " ")
		if v[1] == "newmtl" then
			materials[v[2]] = {
				color = {1.0, 1.0, 1.0, 1.0},
				specular = 0.5,
			}
			mat = materials[v[2]]
		elseif v[1] == "Ks" then
			mat.specular = tonumber(v[2])
		elseif v[1] == "Kd" then
			mat.color[1] = tonumber(v[2])
			mat.color[2] = tonumber(v[3])
			mat.color[3] = tonumber(v[4])
		elseif v[1] == "d" then
			mat.color[4] = tonumber(v[2])
		end
	end
	
	--load object
	local material
	local blocked = false
	for l in love.filesystem.lines(self.objectDir .. name .. ".obj") do
		local v = self:split(l, " ")
		if not blocked then
			if v[1] == "v" then
				vertices[#vertices+1] = {tonumber(v[2]), tonumber(v[3]), -tonumber(v[4])}
			elseif v[1] == "vn" then
				normals[#normals+1] = {tonumber(v[2]), tonumber(v[3]), -tonumber(v[4])}
			elseif v[1] == "vt" then
				texVertices[#texVertices+1] = {tonumber(v[2]), tonumber(v[3])}
			elseif v[1] == "usemtl" then
				material = v[2]
			elseif v[1] == "f" then
				local o
				if splitMargin then
					--split object, where 0|0|0 is the left-front-lower corner of the first object and every splitMargin is a new object with size 1.
					--So each object must be within -margin to splitMargin-margin, a perfect cube will be 0|0|0 to 1|1|1
					local objSize = 1
					local margin = (splitMargin-objSize)/2
					local v2 = self:split(v[2], "/")
					local x, y, z = vertices[tonumber(v2[1])][1], vertices[tonumber(v2[1])][2], vertices[tonumber(v2[1])][3]
					local tx, ty, tz = math.floor((x+margin)/splitMargin)+1, math.floor((z+margin)/splitMargin)+1, math.floor((-y-margin)/splitMargin)+2
					if not obj.objects[tx] then obj.objects[tx] = { } end
					if not obj.objects[tx][ty] then obj.objects[tx][ty] = { } end
					if not obj.objects[tx][ty][tz] then obj.objects[tx][ty][tz] = {faces = { }, final = { }} end
					o = obj.objects[tx][ty][tz]
					o.tx = math.floor((x+margin)/splitMargin)*splitMargin + objSize/2
					o.ty = math.floor((y+margin)/splitMargin)*splitMargin + objSize/2
					o.tz = math.floor((z+margin)/splitMargin)*splitMargin + objSize/2
					--print(tx, ty, tz, "|" .. x, y, z, "|" .. x - o.tx, y - o.ty, z - o.tz)
				else
					o = obj
				end
				
				--combine vertex and data into one
				for i = 1, #v-1 do
					local v2 = self:split(v[i+1], "/")
					o.final[#o.final+1] = {vertices[tonumber(v2[1])], texVertices[tonumber(v2[2])], normals[tonumber(v2[3])], materials[material]}
				end
				
				if #v-1 == 3 then
					--tris
					o.faces[#o.faces+1] = {#o.final-0, #o.final-1, #o.final-2}
				elseif #v-1 == 4 then
					--quad
					o.faces[#o.faces+1] = {#o.final-1, #o.final-2, #o.final-3}
					o.faces[#o.faces+1] = {#o.final-0, #o.final-1, #o.final-3}
				else
					error("only tris and quads supported (got " .. (#v-1) .. " vertices)")
				end
			end
		end
		
		if v[1] == "o" then
			if l:find("frame") then
				blocked = true
			else
				blocked = false
			end
		end
	end
	
	--fill mesh
	if splitMargin then
		for x, dx in pairs(obj.objects) do
			for y, dy in pairs(dx) do
				for z, dz in pairs(dy) do
					--move sub objects
					for i,v in ipairs(dz.final) do
						if not v[1][4] then
							v[1][1] = v[1][1] - (dz.tx or 0)
							v[1][2] = v[1][2] - (dz.ty or 0)
							v[1][3] = v[1][3] - (dz.tz or 0)
							v[1][4] = true
						end
					end
					for i,v in ipairs(dz.final) do
						v[1][4] = nil
					end
					self:createMesh(dz, obj)
				end
			end
		end
	else
		self:createMesh(obj, obj)
	end
	
	return obj
end

--takes an final and face object and a base object and generates the mesh and vertexMap
function lib.createMesh(self, o, obj, faceMap)
	local atypes
	if self.flat then
		atypes = {
		  {"VertexPosition", "float", 3},	-- x, y, z
		  {"VertexTexCoord", "float", 4},	-- normal, specular
		  {"VertexColor", "float", 4},		-- color
		}
	else
		atypes = {
		  {"VertexPosition", "float", 3},	-- x, y, z
		  {"VertexTexCoord", "float", 2},	-- UV
		  {"VertexColor", "float", 3},		-- normal
		}
	end
	
	--compress finals (not all used)
	local vertexMap = { }
	local final = { }
	local finalIDs = { }
	if faceMap then
		for d,f in ipairs(faceMap) do
			finalIDs = { }
			for i = 1, 3 do
				if not finalIDs[f[1][i]] then
					local fc = f[2][f[1][i]]
					local x, z = self:rotatePoint(fc[1][1], fc[1][3], -f[6])
					local nx, nz = self:rotatePoint(fc[3][1], fc[3][3], -f[6])
					final[#final+1] = {{x + f[3], fc[1][2] + f[4], z + f[5]}, fc[2], {nx, fc[3][2], nz}, fc[4]}
					finalIDs[f[1][i]] = #final
				end
				vertexMap[#vertexMap+1] = finalIDs[f[1][i]]
			end
		end
	else
		for d,f in ipairs(o.faces) do
			for i = 1, 3 do
				if not finalIDs[f[i]] then
					final[#final+1] = o.final[f[i]]
					finalIDs[f[i]] = #final
				end
				vertexMap[#vertexMap+1] = finalIDs[f[i]]
			end
		end
	end
	
	--create mesh
	o.mesh = love.graphics.newMesh(atypes, #final, "triangles", "static")
	for d,s in ipairs(final) do
		vertexMap[#vertexMap+1] = s[i]
		local p = s[1]
		local t = s[2]
		local n = s[3]
		local m = s[4]
		if self.flat then
			o.mesh:setVertex(d,
				p[1], p[2], p[3],
				n[1]*0.5+0.5, n[2]*0.5+0.5, n[3]*0.5+0.5,
				m.specular,
				m.color[1], m.color[2], m.color[3], m.color[4]
			)
		else
			--not working yet
			--o.mesh:setVertex(d, p[1], p[2], p[3], t[1], t[2], n[1]*0.5+0.5, n[3]*0.5+0.5, -n[2]*0.5+0.5)
		end
	end
	
	--vertex map
	o.mesh:setVertexMap(vertexMap)
end

--creates a triangle mesh based on position/color/specular (x, y, z, [r, g, b, spec]) points
function lib.loadCustomObject(self, vertices)
	local o = { }
	
	o.vertices = vertices
	for i = 1, #vertices/3 do
		local v1 = vertices[(i-1)*3 + 1]
		local v2 = vertices[(i-1)*3 + 2]
		local v3 = vertices[(i-1)*3 + 3]
		
		local a = {v1[1] - v2[1], v1[2] - v2[2], v1[3] - v2[3]}
		local b = {v1[1] - v3[1], v1[2] - v3[2], v1[3] - v3[3]}
		
		local n = {
			(a[2]*b[3] - a[3]*b[2]),
			(a[3]*b[1] - a[1]*b[3]),
			(a[1]*b[2] - a[2]*b[1]),
		}
		
		local l = math.sqrt(n[1]^2+n[2]^2+n[3]^2)
		n[1] = n[1] / l
		n[2] = n[2] / l
		n[3] = n[3] / l
		
		v1[8] = n[1]
		v1[9] = n[2]
		v1[10] = n[3]
		
		v2[8] = n[1]
		v2[9] = n[2]
		v2[10] = n[3]
		
		v3[8] = n[1]
		v3[9] = n[2]
		v3[10] = n[3]
	end
	
	local atypes = {
		{"VertexPosition", "float", 3},	-- x, y, z
		{"VertexTexCoord", "float", 4},	-- normal, specular
		{"VertexColor", "float", 4},	-- color
	}
	
	--fill mesh
	local lastMaterial
	o.mesh = love.graphics.newMesh(atypes, #vertices, "triangles", "static")
	for d,s in ipairs(vertices) do
		o.mesh:setVertex(d,
			s[1], s[2], s[3],
			s[8]*0.5+0.5, s[9]*0.5+0.5, s[10]*0.5+0.5,
			s[7] or 0.5,
			s[4], s[5], s[6], 1.0
		)
	end
	
	return o
end