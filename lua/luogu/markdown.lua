local M = {}

local function tag(name)
    return (name:gsub('%a', function(c)
        return '[' .. c:lower() .. c:upper() .. ']'
    end))
end

local function attribute(attrs, name)
    local pattern = tag(name)
    return attrs:match('%f[%w]' .. pattern .. '%s*=%s*"([^"]*)"')
        or attrs:match("%f[%w]" .. pattern .. "%s*=%s*'([^']*)'")
end

local symbols = {
    le = '≤', leq = '≤', ge = '≥', geq = '≥', ne = '≠', neq = '≠',
    times = '×', cdot = '·', div = '÷', pm = '±', infty = '∞',
    approx = '≈', equiv = '≡', ['in'] = '∈', notin = '∉', subset = '⊂',
    subseteq = '⊆', cup = '∪', cap = '∩', to = '→', gets = '←',
    sum = '∑', prod = '∏', lfloor = '⌊', rfloor = '⌋',
    lceil = '⌈', rceil = '⌉', ldots = '…', dots = '…',
    alpha = 'α', beta = 'β', gamma = 'γ', delta = 'δ', pi = 'π',
    sigma = 'σ', theta = 'θ', lambda = 'λ', mu = 'μ', omega = 'ω',
}
local superscript = { ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴',
    ['5'] = '⁵', ['6'] = '⁶', ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹',
    ['+'] = '⁺', ['-'] = '⁻', ['='] = '⁼', ['n'] = 'ⁿ', ['i'] = 'ⁱ' }
local subscript = { ['0'] = '₀', ['1'] = '₁', ['2'] = '₂', ['3'] = '₃', ['4'] = '₄',
    ['5'] = '₅', ['6'] = '₆', ['7'] = '₇', ['8'] = '₈', ['9'] = '₉',
    ['+'] = '₊', ['-'] = '₋', ['='] = '₌', ['i'] = 'ᵢ', ['j'] = 'ⱼ',
    ['n'] = 'ₙ', ['k'] = 'ₖ', ['x'] = 'ₓ' }

-- All-or-nothing conversion: unsupported TeX stays intact rather than losing meaning.
local function readable_math(expr, fallback)
    local valid = true
    expr = expr:gsub('\\bm%s*([%w])', '%1')
    expr = expr:gsub('\\(mathbf)%s*{([%w]+)}', function(_, value) return value end)
    expr = expr:gsub('\\(text)%s*{([^{}]+)}', function(_, value) return value end)
    expr = expr:gsub('\\frac%s*{([^{}]+)}%s*{([^{}]+)}', function(a, b)
        return '(' .. a .. ')/(' .. b .. ')'
    end)
    expr = expr:gsub('\\([%a]+)', function(command)
        if not symbols[command] then valid = false; return '\\' .. command end
        return symbols[command]
    end)
    local function script(mark, value)
        local mapping = mark == '^' and superscript or subscript
        local converted = {}
        for c in value:gmatch('.') do
            if not mapping[c] then valid = false; return mark .. '{' .. value .. '}' end
            converted[#converted + 1] = mapping[c]
        end
        return table.concat(converted)
    end
    expr = expr:gsub('([%^_]){([^{}]+)}', script)
    expr = expr:gsub('([%^_])([%w%+%-])', script)
    -- A simple braced atom is grouping only; complex groups are left as TeX.
    expr = expr:gsub('{([%w]+)}', '%1')
    if not valid or expr:find('[\\{}%^_`%[%]]') then return fallback end
    expr = expr:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
    expr = expr:gsub('%*', '\\*')
    return expr
end

-- Stash code and math before interpreting HTML so their contents remain literal.
local function protect(text)
    local saved = {}
    local function stash(value)
        saved[#saved + 1] = value
        return '\1' .. #saved .. '\2'
    end
    local output, i, line_start, fence_char, fence_len = {}, 1, true, nil, nil
    while i <= #text do
        if line_start then
            local line_end = text:find('\n', i, true) or (#text + 1)
            local line = text:sub(i, line_end - 1)
            local indent, run = line:match('^( *)([`~]+)')
            local is_fence = indent and #indent <= 3 and #run >= 3
                and (run:match('^`+$') or run:match('^~+$'))
            if fence_char then
                output[#output + 1] = stash(line)
                if is_fence and run:sub(1, 1) == fence_char and #run >= fence_len
                    and line:sub(#indent + #run + 1):match('^%s*$') then
                    fence_char, fence_len = nil, nil
                end
                i = line_end
            elseif is_fence then
                fence_char, fence_len = run:sub(1, 1), #run
                output[#output + 1] = stash(line)
                i = line_end
            elseif line:match('^    ') or line:match('^\t') then
                output[#output + 1] = stash(line)
                i = line_end
            end
            line_start = false
            if i > #text then break end
        end
        local c = text:sub(i, i)
        if c == '\n' then
            output[#output + 1] = c
            i, line_start = i + 1, true
        elseif c == '<' then
            local rest = text:sub(i)
            local open = rest:match('^(<[pP][rR][eE]%f[%W][^>]*>)')
            local name = open and 'pre'
            if not open then
                open = rest:match('^(<[cC][oO][dD][eE]%f[%W][^>]*>)')
                name = open and 'code'
            end
            local finish
            if open then
                local _, last = text:find('</' .. tag(name) .. '%s*>', i + #open)
                finish = last
            end
            if finish then
                output[#output + 1] = stash(text:sub(i, finish))
                i = finish + 1
            else
                output[#output + 1], i = c, i + 1
            end
        elseif c == '`' then
            local run = text:match('^`+', i)
            local j = i + #run
            local finish
            while j <= #text do
                local a, b = text:find('`+', j)
                if not a then break end
                if b - a + 1 == #run then finish = b; break end
                j = b + 1
            end
            if finish then
                output[#output + 1] = stash(text:sub(i, finish))
                i = finish + 1
            else
                output[#output + 1], i = run, i + #run
            end
        elseif c == '\\' and (text:sub(i + 1, i + 1) == '(' or text:sub(i + 1, i + 1) == '[') then
            local display = text:sub(i + 1, i + 1) == '['
            local close = display and '\\]' or '\\)'
            local finish = text:find(close, i + 2, true)
            if finish then
                local delimiter = display and '$$' or '$'
                local expr = text:sub(i + 2, finish - 1)
                output[#output + 1] = stash(readable_math(expr, delimiter .. expr .. delimiter))
                i = finish + 2
            else
                output[#output + 1], i = c, i + 1
            end
        elseif c == '$' then
            local delim = text:sub(i, i + 1) == '$$' and '$$' or '$'
            local j, finish = i + #delim, nil
            while j <= #text do
                local pos = text:find(delim, j, true)
                if not pos then break end
                local slashes, k = 0, pos - 1
                while k >= i and text:sub(k, k) == '\\' do slashes, k = slashes + 1, k - 1 end
                if slashes % 2 == 0 then finish = pos + #delim - 1; break end
                j = pos + #delim
            end
            if finish then
                local expr = text:sub(i + #delim, finish - #delim)
                local original = text:sub(i, finish)
                if delim == '$' and (expr:match('^%s') or expr:match('%s$')) then
                    output[#output + 1] = stash(original)
                else
                    output[#output + 1] = stash(readable_math(expr, original))
                end
                i = finish + 1
            else
                output[#output + 1], i = delim, i + #delim
            end
        elseif c == '\\' and i < #text then
            output[#output + 1] = stash(text:sub(i, i + 1))
            i = i + 2
        else
            output[#output + 1], i = c, i + 1
        end
    end
    return table.concat(output), saved
end

local function convert_table(original, body)
    -- Complex HTML tables are already valid Markdown HTML; do not lose spans.
    if body:lower():find('colspan', 1, true) or body:lower():find('rowspan', 1, true) then return original end
    local rows, width = {}, nil
    for row in body:gmatch('<' .. tag('tr') .. '[^>]*>(.-)</' .. tag('tr') .. '%s*>') do
        local cells = {}
        for kind, value in row:gmatch('<(' .. tag('t') .. '[hHdD])[^>]*>(.-)</' .. tag('t') .. '[hHdD]%s*>') do
            value = value:gsub('[\r\n]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            value = value:gsub('|', '\\|')
            cells[#cells + 1] = value
        end
        if #cells == 0 or (width and #cells ~= width) then return original end
        width = #cells
        rows[#rows + 1] = '| ' .. table.concat(cells, ' | ') .. ' |'
    end
    if #rows == 0 then return original end
    local separator = {}
    for _ = 1, width do separator[#separator + 1] = '---' end
    table.insert(rows, 2, '| ' .. table.concat(separator, ' | ') .. ' |')
    return '\n\n' .. table.concat(rows, '\n') .. '\n\n'
end

local function markdown(text)
    local saved
    text, saved = protect(text)
    text = text:gsub('<' .. tag('br') .. '%s*/?%s*>', '  \n')
    text = text:gsub('<' .. tag('a') .. '([^>]*)>(.-)</' .. tag('a') .. '%s*>', function(attrs, label)
        local href = attribute(attrs, 'href')
        if not href or href:find('[%s<>]') or label:find('%]') then
            return '<a' .. attrs .. '>' .. label .. '</a>'
        end
        return '[' .. label .. '](' .. href:gsub('([()])', '\\%1') .. ')'
    end)
    for _, spec in ipairs({ { 'sup', '^' }, { 'sub', '_' } }) do
        text = text:gsub('<' .. tag(spec[1]) .. '%s*>(.-)</' .. tag(spec[1]) .. '%s*>', function(value)
            -- Preserve HTML when the contents are too complex to safely express as TeX.
            if value:find('[<>{}$\\\1\2\n]') then return '<' .. spec[1] .. '>' .. value .. '</' .. spec[1] .. '>' end
            return readable_math(spec[2] .. '{' .. value .. '}', '<' .. spec[1] .. '>' .. value .. '</' .. spec[1] .. '>')
        end)
    end
    text = text:gsub('(<[tT][aA][bB][lL][eE][^>]*>(.-)</[tT][aA][bB][lL][eE]%s*>)', convert_table)
    return (text:gsub('\1(%d+)\2', function(n) return saved[tonumber(n)] end))
end

local function append_text(lines, text)
    local start = 1
    while true do
        local pos = text:find('\n', start, true)
        if not pos then
            lines[#lines + 1] = text:sub(start)
            return
        end
        lines[#lines + 1] = text:sub(start, pos - 1)
        start = pos + 1
    end
end

local function section(lines, title, value)
    if type(value) ~= 'string' or value == '' then return end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '## ' .. title
    lines[#lines + 1] = ''
    append_text(lines, markdown(value))
end

local function sample_part(lines, title, value)
    if type(value) ~= 'string' then return end
    lines[#lines + 1] = '### ' .. title
    lines[#lines + 1] = ''
    local longest = 2
    for run in value:gmatch('`+') do longest = math.max(longest, #run) end
    local fence = string.rep('`', longest + 1)
    lines[#lines + 1] = fence
    if value ~= '' then
        -- The newline before the closing fence is structural, not an extra sample line.
        append_text(lines, value:sub(-1) == '\n' and value:sub(1, -2) or value)
    end
    lines[#lines + 1] = fence
    lines[#lines + 1] = ''
end

local function limit_values(value)
    if type(value) == 'number' or type(value) == 'string' then return tostring(value) end
    if type(value) ~= 'table' then return nil end
    local values, seen = {}, {}
    for _, v in ipairs(value) do
        if (type(v) == 'number' or type(v) == 'string') and not seen[tostring(v)] then
            values[#values + 1] = tostring(v)
            seen[tostring(v)] = true
        end
    end
    return #values > 0 and table.concat(values, ', ') or nil
end

function M.document(problem)
    problem = problem or {}
    local content = type(problem.content) == 'table' and problem.content or {}
    local lines = {}
    local title = problem.title or problem.name or content.name
    local pid = problem.pid
    if pid ~= nil or (type(title) == 'string' and title ~= '') then
        local parts = {}
        if pid ~= nil and tostring(pid) ~= '' then parts[#parts + 1] = tostring(pid) end
        if type(title) == 'string' and title ~= '' then parts[#parts + 1] = title end
        if #parts > 0 then lines[#lines + 1] = '# ' .. table.concat(parts, ' ') end
    end
    if pid ~= nil and tostring(pid) ~= '' then
        if #lines > 0 then lines[#lines + 1] = '' end
        lines[#lines + 1] = 'https://www.luogu.com.cn/problem/' .. tostring(pid)
    end
    section(lines, '题目背景', content.background)
    section(lines, '题目描述', content.description)
    section(lines, '输入格式', content.formatI)
    section(lines, '输出格式', content.formatO)
    if type(problem.samples) == 'table' then
        for i, sample in ipairs(problem.samples) do
            if type(sample) == 'table' and (type(sample[1]) == 'string' or type(sample[2]) == 'string') then
                lines[#lines + 1] = ''
                lines[#lines + 1] = '## 样例 ' .. i
                lines[#lines + 1] = ''
                sample_part(lines, '输入', sample[1])
                sample_part(lines, '输出', sample[2])
            end
        end
    end
    section(lines, '说明/提示', content.hint)
    local limits = type(problem.limits) == 'table' and problem.limits or {}
    local time, memory = limit_values(limits.time), limit_values(limits.memory)
    if time or memory then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '## 限制'
        lines[#lines + 1] = ''
        if time then lines[#lines + 1] = '- 时间限制：' .. time .. ' ms' end
        if memory then lines[#lines + 1] = '- 内存限制：' .. memory .. ' KB' end
    end
    return lines
end

return M
