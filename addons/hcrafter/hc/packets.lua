-- packet parsers used by HCrafter. read-only: HCrafter never sends packets.
-- an excerpt of xitools utils/packets.lua (lin, GPL-3.0). the parsers are
-- copied unchanged except these:
-- the synth request no longer reads the inventory slot numbers, which it
-- read 2 bytes apart and so ran past the end of the 0x24 byte packet
-- (LandSandBoat 0x096_combine_ask.h), and it only reads as many materials
-- as the packet holds.
-- the synth result no longer reads isSkillupAllowed and isDesynth from the
-- skill bytes, which hold plain skill ids on LandSandBoat
-- (0x06f_combine_ans.cpp), so those flags meant nothing. it also reads the
-- materials the result lists after the crystal (0x24 to 0x33), when the
-- packet is long enough to hold them.
local bit = require('bit')

local outboundStartSynth = {
    id = 0x096,
    name = 'Start Synth',
    parse = function(packet)
        local startSynth = {
            crystal = struct.unpack('H', packet, 0x06 + 1),
            crystalIdx = struct.unpack('B', packet, 0x08 + 1),
            ingredientCount = struct.unpack('B', packet, 0x09 + 1),
            ingredient = {},
        }

        local count = math.min(8, startSynth.ingredientCount)
        for i=0, count - 1 do
            local offset = 0x0A + (i * 2)
            if offset + 2 > #packet then
                break
            end
            startSynth.ingredient[i] = struct.unpack('H', packet, offset + 1)
        end

        return startSynth
    end,
}

local inboundBasic = {
    id = 0x029,
    name = 'Basic',
    ---@param packet string
    parse = function(packet)
        local basic = {
            sender     = struct.unpack('i4', packet, 0x04 + 1),
            target     = struct.unpack('i4', packet, 0x08 + 1),
            param      = struct.unpack('i4', packet, 0x0C + 1),
            value      = struct.unpack('i4', packet, 0x10 + 1),
            sender_tgt = struct.unpack('i2', packet, 0x14 + 1),
            target_tgt = struct.unpack('i2', packet, 0x16 + 1),
            message    = struct.unpack('i2', packet, 0x18 + 1),
        }

        return basic
    end
}

local inboundSynthAnimation = {
    id = 0x030,
    name = 'Synth Animation',
    ---@param packet string
    parse = function(packet)
        local synthAnimation = {
            player = struct.unpack('I4', packet, 0x04 + 1),
            playerIdx = struct.unpack('H', packet, 0x08 + 1),
            effect = struct.unpack('H', packet, 0x0A + 1),
            param = struct.unpack('B', packet, 0x0C + 1),
            animation = struct.unpack('B', packet, 0x0D + 1),
        }

        return synthAnimation
    end
}

local inboundCharSkills = {
    id = 0x062,
    name = 'Character Skills',
    ---@param packet string
    parse = function(packet)
        local skillsUpdate = {
            combatSkills = {},
            craftSkills = {},
        }

        for i=0, 0x2F do
            skillsUpdate.combatSkills[i] = {
                level = bit.band(struct.unpack('H', packet, 0x80 + (i * 2) + 1), 0x7FFF),
                isCapped = bit.band(struct.unpack('H', packet, 0x80 + (i * 2) + 1), 0x8000) == 0x8000,
            }
        end

        for i=0, 0x09 do
            skillsUpdate.craftSkills[i] = {
                rank = bit.band(struct.unpack('H', packet, 0xE0 + (i * 2) + 1), 0x001F),
                level = bit.rshift(bit.band(struct.unpack('H', packet, 0xE0 + (i * 2) + 1), 0x7FE0), 5),
                isCapped = bit.band(struct.unpack('H', packet, 0xE0 + (i * 2) + 1), 0x8000) == 0x8000,
            }
        end

        return skillsUpdate
    end
}

local inboundSynthResultPlayer = {
    id = 0x06F,
    name = 'Self Synth',
    ---@param packet string
    parse = function(packet)
        local selfSynth = {
            result = struct.unpack('B', packet, 0x04 + 1),
            quality = struct.unpack('b', packet, 0x05 + 1),
            count = struct.unpack('B', packet, 0x06 + 1),
            item = struct.unpack('H', packet, 0x08 + 1),
            lost = {
                [1] = struct.unpack('H', packet, 0x0A + 1),
                [2] = struct.unpack('H', packet, 0x0C + 1),
                [3] = struct.unpack('H', packet, 0x0E + 1),
                [4] = struct.unpack('H', packet, 0x10 + 1),
                [5] = struct.unpack('H', packet, 0x12 + 1),
                [6] = struct.unpack('H', packet, 0x14 + 1),
                [7] = struct.unpack('H', packet, 0x16 + 1),
                [8] = struct.unpack('H', packet, 0x18 + 1),
            },
            skill = {
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1A + 1), 63),
                },
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1B + 1), 63),
                },
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1C + 1), 63),
                },
                {
                    skillId = bit.band(struct.unpack('B', packet, 0x1D + 1), 63),
                },
            },
            skillup = {
                [1] = struct.unpack('B', packet, 0x1E + 1),
                [2] = struct.unpack('B', packet, 0x1F + 1),
                [3] = struct.unpack('B', packet, 0x20 + 1),
                [4] = struct.unpack('B', packet, 0x21 + 1),
            },
            crystal = struct.unpack('H', packet, 0x22 + 1),
            materials = { },
        }

        if #packet >= 0x24 + 16 then
            for i = 0, 7 do
                selfSynth.materials[i + 1] = struct.unpack('H', packet, 0x24 + (i * 2) + 1)
            end
        end

        return selfSynth
    end
}

return {
    outbound = {
        startSynth = outboundStartSynth,
    },
    inbound = {
        basic = inboundBasic,
        synthAnimation = inboundSynthAnimation,
        charSkills = inboundCharSkills,
        synthResultPlayer = inboundSynthResultPlayer,
    },
}
