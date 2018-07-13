--[[
Title: Import_svg.lua
Author(s): leio
Date: 2017/6/14
Desc: 
use the lib:
------------------------------------------------------------
NPL.load("(gl)Mod/NplCadLibrary/services/interface/Import_svg.lua");
------------------------------------------------------------
]]
NPL.load("(gl)Mod/NplCadLibrary/services/NplCadEnvironment.lua");
local NplCadEnvironment = commonlib.gettable("Mod.NplCadLibrary.services.NplCadEnvironment");

NPL.load("(gl)Mod/NplCadLibrary/core/Node.lua");
NPL.load("(gl)Mod/NplCadLibrary/drawables/CSGModel.lua");
NPL.load("(gl)Mod/NplCadLibrary/drawables/CAGModel.lua");
NPL.load("(gl)Mod/NplCadLibrary/csg/CSGFactory.lua");
NPL.load("(gl)Mod/NplCadLibrary/cag/CAGFactory.lua");
NPL.load("(gl)Mod/NplCadLibrary/cag/CAG.lua");
NPL.load("(gl)Mod/NplCadLibrary/utils/SVGHelpers.lua");
local Node = commonlib.gettable("Mod.NplCadLibrary.core.Node");
local CSGModel = commonlib.gettable("Mod.NplCadLibrary.drawables.CSGModel");
local CSGFactory = commonlib.gettable("Mod.NplCadLibrary.csg.CSGFactory");
local CAGFactory = commonlib.gettable("Mod.NplCadLibrary.cag.CAGFactory");
local CAGModel = commonlib.gettable("Mod.NplCadLibrary.drawables.CAGModel");
local CAG = commonlib.gettable("Mod.NplCadLibrary.cag.CAG");
local XPath = commonlib.XPath
local SVGHelpers = commonlib.gettable("Mod.NplCadLibrary.utils.SVGHelpers");

local pi = NplCadEnvironment.pi;
local is_string = NplCadEnvironment.is_string;
local is_table = NplCadEnvironment.is_table;
local is_number = NplCadEnvironment.is_number;
local is_array = NplCadEnvironment.is_array;
local is_node = NplCadEnvironment.is_node;
local is_shape = NplCadEnvironment.is_shape;
local is_path = NplCadEnvironment.is_path;

function NplCadEnvironment.import_svg(filename)
	local self = getfenv(2);
	return self:import_svg__(filename);
end
function NplCadEnvironment:import_svg__(filename)
	local parent = self:getNode__();

	local node = NplCadEnvironment.read_import_svg(filename);
	parent:addChild(node);
	return node;
end
function NplCadEnvironment.read_import_svg(filename)
	commonlib.echo("=============read_import_svg");
	commonlib.echo(filename);

	local node
	if (not ParaIO.DoesFileExist(filename, false)) then
		commonlib.echo("File "..filename.." not exist!")
	else
		local xmlRoot
		local file = ParaIO.open(filename, "r")
		if (file:IsValid()) then
			local svgXml = file:GetText()
			file:close();
			local s, e = string.find(svgXml, "<svg")
			svgXml = string.sub(svgXml, s)
			xmlRoot = ParaXML.LuaXML_ParseString(svgXml)
		end
		node = NplCadEnvironment.SVGParser(xmlRoot)
	end

	return node;
end

function NplCadEnvironment.SVGParser(xmlRoot)
	local node = Node.create("")
	if not xmlRoot then
		return node
	end

	for __, v in ipairs(xmlRoot) do
		local svgObj = NplCadEnvironment.svgSvg(v.name, v.attr)
		if svgObj then
			node = NplCadEnvironment.svgGroup(v, svgObj)
			break
		end
	end

	return node
end

function NplCadEnvironment.svgSvg(name, attr)
	local svgObj
	if (name == "svg" and attr) then
		svgObj = svgObj or {}
		svgObj.pxPmm = attr.pxpmm or SVGHelpers.pxPmm
		svgObj.unitsPmm = {svgObj.pxPmm, svgObj.pxPmm}
		svgObj.width= attr.width
		svgObj.height= attr.height

		local viewBox = attr.viewBox
		if viewBox then
			local v1, v2, v3, v4 = string.match(viewBox, "[%s]*(.-)[%s,]+(.-)[%s,]+(.-)[%s,]+(.+)[%s,]*")
			svgObj.viewX = SVGHelpers.parseFloat(v1)
			svgObj.viewY = SVGHelpers.parseFloat(v2)
			svgObj.viewW = SVGHelpers.parseFloat(v3)
			svgObj.viewH = SVGHelpers.parseFloat(v4)
			
			if string.find(svgObj.width, "%%") then
				local u = svgObj.unitsPmm[1] * (SVGHelpers.parseFloat(svgObj.width) / 100.0)
				svgObj.unitsPmm[1] = u
			else
				local s = SVGHelpers.css2cag(svgObj.width, SVGHelpers.pxPmm)
				s = svgObj.viewW / s
				svgObj.unitsPmm[1] = s
			end

			if string.find(svgObj.height, "%%") then
				local u = svgObj.unitsPmm[2] * (SVGHelpers.parseFloat(svgObj.height) / 100.0)
				svgObj.unitsPmm[2] = u
			else
				local s = SVGHelpers.css2cag(svgObj.height, SVGHelpers.pxPmm)
				s = svgObj.viewH / s
				svgObj.unitsPmm[2] = s
			end
		else
			svgObj.viewX = 0
			svgObj.viewY = 0
			svgObj.viewW = 1920 / svgObj.unitsPmm[1] -- average screen size / pixels per unit
			svgObj.viewH = 1080 / svgObj.unitsPmm[2] -- screen size 1920 * 1080
		end
		svgObj.viewP = math.sqrt(svgObj.viewW * svgObj.viewW + svgObj.viewH * svgObj.viewH) / math.sqrt(2)
	end
	return svgObj
end

function NplCadEnvironment.svgGroup(group, svgObj)
	local node = Node.create("")
	local svgObjectMap = {
		["rect"] = NplCadEnvironment.svgRect,
		["circle"] = NplCadEnvironment.svgCircle,
		["ellipse"] = NplCadEnvironment.svgEllipse,
		["line"] = NplCadEnvironment.svgLine,
		["polyline"] = NplCadEnvironment.svgPolyline,
		["polygon"] = NplCadEnvironment.svgPolygon,
		["path"] = NplCadEnvironment.svgPath,
		["use"] = NplCadEnvironment.svgUse,
		["desc"] = NplCadEnvironment.svgIgnored,
		["defs"] = NplCadEnvironment.svgIgnored,
		["title"] = NplCadEnvironment.svgIgnored,
		["style"] = NplCadEnvironment.svgIgnored,
	}

	for k, shape in ipairs(group) do
		if (shape.name == "g") then
			local child = NplCadEnvironment.svgGroup(shape, svgObj)
			if (shape.attr) then
				NplCadEnvironment.svgTransforms(shape.attr, svgObj, child)
				NplCadEnvironment.svgCore(shape.attr, svgObj, child)
				NplCadEnvironment.svgPresentation(shape.attr, svgObj, child)
			end
			node:addChild(child)
		else
			if (shape.name and shape.attr) then
				if (svgObjectMap[shape.name]) then
					local child = svgObjectMap[shape.name](shape.attr, svgObj)
					if (child) then node:addChild(child) end
				else
					commonlib.echo("Warning: Unsupported SVG element: "..shape.name)
				end
			end
		end
	end

	return node
end

function NplCadEnvironment.svgRect(attr, svgObj)
	if (attr) then
		local x = SVGHelpers.cagLengthX(attr.x, svgObj.unitsPmm, svgObj.viewW)
		local y = 0 - SVGHelpers.cagLengthY(attr.y, svgObj.unitsPmm, svgObj.viewH)
		local w = SVGHelpers.cagLengthX(attr.width, svgObj.unitsPmm, svgObj.viewW)
		local h = SVGHelpers.cagLengthY(attr.height, svgObj.unitsPmm, svgObj.viewH)
		local rx = SVGHelpers.cagLengthX(attr.rx, svgObj.unitsPmm, svgObj.viewW)
		local ry = SVGHelpers.cagLengthY(attr.ry, svgObj.unitsPmm, svgObj.viewH)
		if (w > 0 and h > 0) then
			x = x + w / 2
			y = y - h / 2
			if (rx > 0 and ry > 0) then
				rx = math.min(rx, ry)
			else
				rx = math.max(rx, ry)
			end
			local options = {center = {x, y}, radius = {w/2, h/2}, roundradius = rx, resolution = 32}
			local node = NplCadEnvironment.read_roundedRectangle(options)
			NplCadEnvironment.svgTransforms(attr, svgObj, node)
			NplCadEnvironment.svgCore(attr, svgObj, node)
			NplCadEnvironment.svgPresentation(attr, svgObj, node)
			return node
		end
	end
	return nil
end

function NplCadEnvironment.svgCircle(attr, svgObj)
	if (attr) then
		local x1 = SVGHelpers.cagLengthX(attr.cx, svgObj.unitsPmm, svgObj.viewW)
		local y1 = 0 - SVGHelpers.cagLengthY(attr.cy, svgObj.unitsPmm, svgObj.viewH)
		local radius = SVGHelpers.cagLengthP(attr.r, svgObj.unitsPmm, svgObj.viewP)

		if (radius > 0) then
			local options = {r = radius, center = {x1, y1}}
			local node = NplCadEnvironment.read_circle(options)
			NplCadEnvironment.svgTransforms(attr, svgObj, node)
			NplCadEnvironment.svgCore(attr, svgObj, node)
			NplCadEnvironment.svgPresentation(attr, svgObj, node)
			return node
		end
	end
	return nil
end

function NplCadEnvironment.svgEllipse(attr, svgObj)
	if (attr) then
		local x1 = SVGHelpers.cagLengthX(attr.cx, svgObj.unitsPmm, svgObj.viewW)
		local y1 = 0 - SVGHelpers.cagLengthY(attr.cy, svgObj.unitsPmm, svgObj.viewH)
		local rx = SVGHelpers.cagLengthP(attr.rx, svgObj.unitsPmm, svgObj.viewW)
		local ry = SVGHelpers.cagLengthP(attr.ry, svgObj.unitsPmm, svgObj.viewH)

		if (rx> 0 and ry > 0) then
			local options = {center = {x1, y1}, radius = {rx, ry}}
			commonlib.echo(options)
			local node = NplCadEnvironment.read_ellipse(options)
			NplCadEnvironment.svgTransforms(attr, svgObj, node)
			NplCadEnvironment.svgCore(attr, svgObj, node)
			NplCadEnvironment.svgPresentation(attr, svgObj, node)
			return node
		end
	end
	return nil
end

function NplCadEnvironment.svgLine(attr, svgObj)
	if (attr) then
		local x1 = SVGHelpers.cagLengthX(attr.x1, svgObj.unitsPmm, svgObj.viewW)
		local y1 = 0 - SVGHelpers.cagLengthY(attr.y1, svgObj.unitsPmm, svgObj.viewH)
		local x2 = SVGHelpers.cagLengthX(attr.x2, svgObj.unitsPmm, svgObj.viewW)
		local y2 = 0 - SVGHelpers.cagLengthY(attr.y2, svgObj.unitsPmm, svgObj.viewH)

		local r = SVGHelpers.cssPxUnit
		if (attr["stroke-width"]) then
			r = SVGHelpers.cagLengthP(attr["stroke-width"], svgObj.unitsPmm, svgObj.viewP) / 2
		else
			
		end
		local options = {{x1, y1}, {x2, y2}}
		local node = NplCadEnvironment.read_expandToCAG(r, NplCadEnvironment.path2d(options))
		NplCadEnvironment.svgTransforms(attr, svgObj, node)
		NplCadEnvironment.svgCore(attr, svgObj, node)
		NplCadEnvironment.svgPresentation(attr, svgObj, node)
		return node
	end
	return nil
end

function NplCadEnvironment.svgPolyline(attr, svgObj)
	if (attr and attr.points) then
		commonlib.echo(attr.points)
		local options = {}
		local points = commonlib.split(attr.points, " ")
		for i = 0, #points do
			local v = commonlib.split(points[i], ",")
			local x = tonumber(v[1])
			local y = tonumber(v[2])
			if (x and y) then
				x = SVGHelpers.cagLengthX(x, svgObj.unitsPmm, svgObj.viewW)
				y = 0 - SVGHelpers.cagLengthY(y, svgObj.unitsPmm, svgObj.viewH)
				table.insert(options, {x, y})	
			end
		end

		local r = SVGHelpers.cssPxUnit
		if (attr["stroke-width"]) then
			r = SVGHelpers.cagLengthP(attr["stroke-width"], svgObj.unitsPmm, svgObj.viewP) / 2
		else
			
		end
		local node = NplCadEnvironment.read_expandToCAG(r, NplCadEnvironment.path2d(options))
		NplCadEnvironment.svgTransforms(attr, svgObj, node)
		NplCadEnvironment.svgCore(attr, svgObj, node)
		NplCadEnvironment.svgPresentation(attr, svgObj, node)
		return node
	end
	return nil
end

function NplCadEnvironment.svgPolygon(attr, svgObj)
	if (attr and attr.points) then
		commonlib.echo(attr.points)
		local options = {}
		local points = commonlib.split(attr.points, ", ")
		for i = 1, (#points)-1, 2 do
			local x = tonumber(points[i])
			local y = tonumber(points[i + 1])
			if (x and y) then
				x = SVGHelpers.cagLengthX(x, svgObj.unitsPmm, svgObj.viewW)
				y = 0 - SVGHelpers.cagLengthY(y, svgObj.unitsPmm, svgObj.viewH)
				table.insert(options, {x, y})	
			end
		end

		local node = NplCadEnvironment.read_innerToCAG(NplCadEnvironment.path2d({points = options, closed = true}))
		NplCadEnvironment.svgTransforms(attr, svgObj, node)
		NplCadEnvironment.svgCore(attr, svgObj, node)
		NplCadEnvironment.svgPresentation(attr, svgObj, node)
		return node
	end
	return nil
end

function NplCadEnvironment.svgPath(attr, svgObj)
	if (attr and attr.d) then
		local commands = {}
		local co
		local bf = ""
		for i = 1, #attr.d do
			local c = string.sub(attr.d, i, i)
			if (c == '-') then
				if (#bf > 0) then
					table.insert(co.points, bf)
					bf = ""
				end
				bf = bf..c
			elseif (c == '.') then
				if (#bf > 0 and string.find(bf, "%.")) then
					table.insert(co.points, bf)
					bf = ""
				end
				bf = bf..c
			elseif (c >= '0' and c <= '9') then
				bf = bf..c
			elseif ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) then
				if (co) then
					if (#bf > 0) then
					table.insert(co.points, bf)
						bf = ""
					end
					table.insert(commands, co)
				else
					co = {}
				end
				co = {command = c, points = {}}
			elseif (c == ',' or c == ' ' or c == '\n') then
				if (co) then
					if (#bf > 0) then
					table.insert(co.points, bf)
						bf = ""
					end
				end
			else
				commonlib.echo("warnning: the path has invalid data")
			end
		end

		if (co) then
			if (#bf > 0) then
				table.insert(co.points, bf)
			end
			table.insert(commands, co)
		end

		local node = NplCadEnvironment.readSvgPath(commands, svgObj)
		NplCadEnvironment.svgTransforms(attr, svgObj, node)
		NplCadEnvironment.svgCore(attr, svgObj, node)
		NplCadEnvironment.svgPresentation(attr, svgObj, node)
		return node
	end
	return nil
end

function NplCadEnvironment.readSvgPath(obj, svgObj)
	local r = SVGHelpers.cssPxUnit
	--[[
	if (attr["stroke-width"]) then
		r = SVGHelpers.cagLengthP(attr["stroke-width"], svgObj.unitsPmm, svgObj.viewP) / 2
	else
	end
	]]

	local paths = {}
	local on = ""
	local sx = 0 sy = 0 cx = 0 cy = 0
	local pi = 1 pc = false
	local bx = 0 by = 0 qx = 0 qy = 0
	local children = {}

	local begin = true
	for n = 1, #obj do
		local command = obj[n].command
		local points = obj[n].points
		if (command == 'm') then
			if (begin) then begin = false cx = 0 cy = 0 end
			if (pi > 1 and (not pc)) then
				NplCadEnvironment.read_expandToCAG(r, paths[pi])	
			end

			if (#points >= 2) then
				cx = cx + SVGHelpers.parseFloat(points[1])
				cy = cy + SVGHelpers.parseFloat(points[2])
				pi = pi + 1
				pc = false
				paths[pi] = NplCadEnvironment.path2d(
					{points = {{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}}, closed = false}
				)
				sx = cx sy = cy
			end

			local i = 3
			while (#points - 2 * i >= 0) do
				local index = 3 + 2 * (i - 3)
				cx = cx + SVGHelpers.parseFloat(points[index])
				cy = cy + SVGHelpers.parseFloat(points[index + 1])
				paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
				i = i + 1
			end
		elseif (command == 'M') then
			if (pi > 1 and (not pc)) then
				NplCadEnvironment.read_expandToCAG(r, paths[pi])
			end

			if (#points >= 2) then
				cx = SVGHelpers.parseFloat(points[1])
				cy = SVGHelpers.parseFloat(points[2])
				pi = pi + 1
				pc = false
				paths[pi] = NplCadEnvironment.path2d(
					{points = {{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}}, closed = false}
				)
				sx = cx sy = cy
			end
			
			local i = 3
			while (#points - 2 * i >= 0) do
				local index = 3 + 2 * (i - 3)
				cx = SVGHelpers.parseFloat(points[index])
				cy = SVGHelpers.parseFloat(points[index + 1])
				paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
				i = i + 1
			end
		elseif (command == 'a') then
			local i = 1
			while (#points - 7 * i >= 0) do
				local index = 1 + 7 * (i - 1)
				local rx = SVGHelpers.parseFloat(points[index])
				local ry = SVGHelpers.parseFloat(points[index + 1])
				local ro = 0 - SVGHelpers.parseFloat(points[index + 2]) -- x-aixs-rotation
				local lf = (points[index + 3] == "1") -- large-arc-flag
				local sf = (points[index + 4] == "1") -- sweep-flag
				cx = cx + SVGHelpers.parseFloat(points[index + 5])
				cy = cy + SVGHelpers.parseFloat(points[index + 6])
				paths[pi] = paths[pi]:appendArc(
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)},
					{xradius = SVGHelpers.svg2cagX(rx, svgObj.unitsPmm), yradius = SVGHelpers.svg2cagY(ry, svgObj.unitsPmm), xaxisrotation = ro, clockwise = sf, large = lf}
				)
				i = i + 1
			end
		elseif (command == 'A') then
			local i = 1
			while (#points - 7 * i >= 0) do
				local index = 1 + 7 * (i - 1)
				local rx = SVGHelpers.parseFloat(points[index])
				local ry = SVGHelpers.parseFloat(points[index + 1])
				local ro = 0 - SVGHelpers.parseFloat(points[index + 2]) -- x-aixs-rotation
				local lf = (points[index + 3] == "1") -- large-arc-flag
				local sf = (points[index + 4] == "1") -- sweep-flag
				cx = SVGHelpers.parseFloat(points[index + 5])
				cy = SVGHelpers.parseFloat(points[index + 6])
				paths[pi] = paths[pi]:appendArc(
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)},
					{xradius = SVGHelpers.svg2cagX(rx, svgObj.unitsPmm), yradius = SVGHelpers.svg2cagY(ry, svgObj.unitsPmm), xaxisrotation = ro, clockwise = sf, large = lf}
				)
				i = i + 1
			end
		elseif (command == 'c') then
			local i = 1
			while (#points - 6 * i >= 0) do
				local index = 1 + 6 * (i - 1)
				local x1 = cx + SVGHelpers.parseFloat(points[index])
				local y1 = cy + SVGHelpers.parseFloat(points[index + 1])
				bx = cx + SVGHelpers.parseFloat(points[index + 2])
				by = cy + SVGHelpers.parseFloat(points[index + 3])
				cx = cx + SVGHelpers.parseFloat(points[index + 4])
				cy = cy + SVGHelpers.parseFloat(points[index + 5])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(x1, svgObj.unitsPmm), SVGHelpers.svg2cagY(y1, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(bx, svgObj.unitsPmm), SVGHelpers.svg2cagY(by, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}	
				)
				bx, by = SVGHelpers.reflect(bx, by, cx, cy)
				i = i + 1
			end
		elseif (command == 'C') then
			local i = 1
			while (#points - 6 * i >= 0) do
				local index = 1 + 6 * (i - 1)
				local x1 = SVGHelpers.parseFloat(points[index])
				local y1 = SVGHelpers.parseFloat(points[index + 1])
				bx = SVGHelpers.parseFloat(points[index + 2])
				by = SVGHelpers.parseFloat(points[index + 3])
				cx = SVGHelpers.parseFloat(points[index + 4])
				cy = SVGHelpers.parseFloat(points[index + 5])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(x1, svgObj.unitsPmm), SVGHelpers.svg2cagY(y1, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(bx, svgObj.unitsPmm), SVGHelpers.svg2cagY(by, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}	
				)
				bx, by = SVGHelpers.reflect(bx, by, cx, cy)
				i = i + 1
			end
		elseif (command == 'q') then
			local i = 1
			while (#points - 4 * i >= 0) do
				local index = 1 + 4 * (i - 1)
				qx = cx + SVGHelpers.parseFloat(points[index])
				qy = cy + SVGHelpers.parseFloat(points[index + 1])
				cx = cx + SVGHelpers.parseFloat(points[index + 2])
				cy = cy + SVGHelpers.parseFloat(points[index + 3])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}
				)
				qx, qy = SVGHelpers.reflect(qx, qy, cx, cy)
				i = i + 1
			end
		elseif (command == 'Q') then
			local i = 1
			while (#points - 4 * i >= 0) do
				local index = 1 + 4 * (i - 1)
				qx = SVGHelpers.parseFloat(points[index])
				qy = SVGHelpers.parseFloat(points[index + 1])
				cx = SVGHelpers.parseFloat(points[index + 2])
				cy = SVGHelpers.parseFloat(points[index + 3])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}
				)
				qx, qy = SVGHelpers.reflect(qx, qy, cx, cy)
				i = i + 1
			end
		elseif (command == 't') then
			local i = 1
			while (#points - 2 * i >= 0) do
				local index = 1 + 2 * (i - 1)
				cx = cx + SVGHelpers.parseFloat(points[index])
				cy = cy + SVGHelpers.parseFloat(points[index + 1])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}	
				)
				qx, qy = SVGHelpers.reflect(qx, qy, cx, cy)
				i = i + 1
			end
		elseif (command == 'T') then
			local i = 1
			while (#points - 2 * i >= 0) do
				local index = 1 + 2 * (i - 1)
				cx = SVGHelpers.parseFloat(points[index])
				cy = SVGHelpers.parseFloat(points[index + 1])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(qx, svgObj.unitsPmm), SVGHelpers.svg2cagY(qy, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}	
				)
				qx, qy = SVGHelpers.reflect(qx, qy, cx, cy)
				i = i + 1
			end
		elseif (command == 's') then
			local i = 1
			while (#points - 4 * i >= 0) do
				local index = 1 + 4 * (i - 1)
				local x1 = bx
				local y1 = by
				bx = cx + SVGHelpers.parseFloat(points[index])
				by = cy + SVGHelpers.parseFloat(points[index + 1])
				cx = cx + SVGHelpers.parseFloat(points[index + 2])
				cy = cy + SVGHelpers.parseFloat(points[index + 3])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(x1, svgObj.unitsPmm), SVGHelpers.svg2cagY(y1, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(bx, svgObj.unitsPmm), SVGHelpers.svg2cagY(by, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}
				)
				bx, by = SVGHelpers.reflect(bx, by, cx, cy)
				i = i + 1
			end
		elseif (command == 'S') then
			local i = 1
			while (#points - 4 * i >= 0) do
				local index = 1 + 4 * (i - 1)
				local x1 = bx
				local y1 = by
				bx = SVGHelpers.parseFloat(points[index])
				by = SVGHelpers.parseFloat(points[index + 1])
				cx = SVGHelpers.parseFloat(points[index + 2])
				cy = SVGHelpers.parseFloat(points[index + 3])
				paths[pi] = paths[pi]:appendBezier(
					{{SVGHelpers.svg2cagX(x1, svgObj.unitsPmm), SVGHelpers.svg2cagY(y1, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(bx, svgObj.unitsPmm), SVGHelpers.svg2cagY(by, svgObj.unitsPmm)},
					{SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)}},
					{resolution = 32}
				)
				bx, by = SVGHelpers.reflect(bx, by, cx, cy)
				i = i + 1
			end
		elseif (command == 'h') then
			for i = 1, #points do
				cx = cx + SVGHelpers.parseFloat(points[i])
				paths[pi] = paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
			end
		elseif (command == 'H') then
			for i = 1, #points do
				cx = SVGHelpers.parseFloat(points[i])
				paths[pi] = paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
			end
		elseif (command == 'l') then
			local i = 1
			while (#points - 2 * i >= 0) do
				local index = 1 + 2 * (i - 1)
				cx = cx + SVGHelpers.parseFloat(points[index])
				cy = cy + SVGHelpers.parseFloat(points[index + 1])
				paths[pi] = paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
				i = i + 1
			end
		elseif (command == 'L') then
			local i = 1
			while (#points - 2 * i >= 0) do
				local index = 1 + 2 * (i - 1)
				cx = SVGHelpers.parseFloat(points[index])
				cy = SVGHelpers.parseFloat(points[index + 1])
				paths[pi] = paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
				i = i + 1
			end
		elseif (command == 'v') then
			for i = 1, #points do
				cy = cy + SVGHelpers.parseFloat(points[i])
				paths[pi] = paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
			end
		elseif (command == 'V') then
			for i = 1, #points do
				cy = SVGHelpers.parseFloat(points[i])
				paths[pi] = paths[pi]:appendPoint({SVGHelpers.svg2cagX(cx, svgObj.unitsPmm), SVGHelpers.svg2cagY(cy, svgObj.unitsPmm)})
			end
		elseif (command == 'z' or command == 'Z') then
			table.insert(children, NplCadEnvironment.read_innerToCAG(paths[pi]:close()))
			cx = sx
			cy = sy
			pc = true
		else
			commonlib.echo("Warning: Unknow PATH command: "..command)
		end
	end

	if (pi > 0 and (not pc)) then
		table.insert(children, NplCadEnvironment.read_expandToCAG(r, paths[pi]))	
	end
	return NplCadEnvironment.read_group({action = "union"}, unpack(children))
end

function NplCadEnvironment.svgUse(attr, svgObj)
	return nil
end

function NplCadEnvironment.svgIgnored(attr, svgObj)
	return nil
end

function NplCadEnvironment.svgCore(attr, svgObj, node)
	if (node and attr.id) then node:setId(attr.id) end
end

function NplCadEnvironment.svgPresentation(attr, svgObj, node)
	if (attr.display and attr.display == "none") then node:setEnabled(false) end
	if (attr.color) then end
	if (attr.opacity) then end
	if (attr.fill) then
		NplCadEnvironment:color__(SVGHelpers.cagColor(attr.fill), node)		
	else
		local s = SVGHelpers.cssStyle(attr, "fill")
		if (s) then
			NplCadEnvironment:color__(SVGHelpers.cagColor(s), node)		
		end
	end
	if (attr["fill-opacity"]) then end
	if (attr["stroke-width"]) then
	else
	end	
	if (attr.stroke) then
	else
	end
	if (attr["stroke-opacity"]) then end
end

function NplCadEnvironment.svgTransforms(attr, svgObj, node)
	local transform = attr.transform
	transform = transform or SVGHelpers.cssStyle(attr, "transform")
	if (not transform) then return end

	-- do scale
	local scale = commonlib.split(string.match(transform, "%s*scale%s*%(%s*(.-)%s*%)"), ", ")
	if (#scale > 0) then
		commonlib.echo(scale)
		local x = tonumber(scale[1])
		local y = tonumber(scale[2])
		x = x or 1
		y = y or x
		NplCadEnvironment:scale__({x, y, 1}, node)
	end

	-- do rotate
	local rotate = commonlib.split(string.match(transform, "%s*rotate%s*%(%s*(.-)%s*%)"), ", ")
	if (#rotate > 0) then
		commonlib.echo(rotate)
		local x = tonumber(rotate[1])
		x = x or 0
		NplCadEnvironment:rotate__({0, 0, -x}, node)
	end

	-- do translate
	local translate = commonlib.split(string.match(transform, "%s*translate%s*%(%s*(.-)%s*%)"), ", ")
	if (#translate > 0) then
		commonlib.echo(translate)
		local x = tonumber(translate[1])
		local y = tonumber(translate[2])
		x = SVGHelpers.cagLengthX(x, svgObj.unitsPmm, svgObj.viewW)
		y = 0 - SVGHelpers.cagLengthY(y, svgObj.unitsPmm, svgObj.viewH)
		NplCadEnvironment:translate__(x, y, 0, node)
	end
end
