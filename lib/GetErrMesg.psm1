function Get-ErrMesg()
{
    $err_mesgs = @(
        "What?",
        "Are you feeling alright?",
        "Hmm, maybe if you speak up, I'll understand...",
        "INVALID COMMAND!!!  Just kidding...actually not really.  I really don't know what you mean...",
        "PC LOAD LETTER",
        "If only I could read minds, then maybe I'd understand...",
        "DOES YOUR MOTHER KNOW WHAT YOU TYPE WITH THOSE HANDS? ...because I don't.",
        "I would if I could, but I can't...",
        "The clouds in the sky are clearer than that.",
        "HOW DARE YOU?!  I mean, I have no idea what that means, but I'm sure it's terrible.",
        "I WOULD NEVER!!!  Mostly because I have no idea how to do that.",
        "LOL, that's hilarious!  Err, wait, oh, you wanted me to do what again?",
        "I mean, is that even legal?",
        "DOES NOT COMPUTE!!!",
# the following are from the sudo source code: https://www.sudo.ws/repos/sudo/file/d491ed281726/plugins/sudoers
<#
/*
 * Copyright (c) 1996, 1998, 1999 Todd C. Miller <Todd.Miller@courtesan.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
#>
<#
    /*
     * HAL insults (paraphrased) from 2001.
     */
#>
    "Just what do you think you're doing Dave?",
    "It can only be attributed to human error.",
    "That's something I cannot allow to happen.",
    "My mind is going. I can feel it.",
    "Sorry about this, I know it's a bit silly.",
    "Take a stress pill and think things over.",
    "This mission is too important for me to allow you to jeopardize it.",
    "I feel much better now.",
<#
    /*
     * Insults from the original sudo(8).
     */
#>
    "Wrong!  You cheating scum!",
    "And you call yourself a Rocket Scientist!",
    "Where did you learn to type?",
    "Are you on drugs?",
    "My pet ferret can type better than you!",
    "You type like i drive.",
    "Do you think like you type?",
    "Your mind just hasn't been the same since the electro-shock, has it?",
<#
    /*
     * CSOps insults (may be site dependent).
     */
#>
    "Maybe if you used more than just two fingers...",
    "BOB says:  You seem to have forgotten your passwd, enter another!",
    "stty: unknown mode: doofus",
    "I can't hear you -- I'm using the scrambler.",
    "The more you drive -- the dumber you get.",
    "Listen, broccoli brains, I don't have time to listen to this trash.",
    "I've seen penguins that can type better than that.",
    "Have you considered trying to match wits with a rutabaga?",
    "You speak an infinite deal of nothing",
<#
    /*
     * Insults from the "Goon Show."
     */
#>
    "You silly, twisted boy you.",
    "He has fallen in the water!",
    "We'll all be murdered in our beds!",
    "You can't come in. Our tiger has got flu",
    "I don't wish to know that.",
    "What, what, what, what, what, what, what, what, what, what?",
    "You can't get the wood, you know.",
    "You'll starve!",
    "... and it used to be so popular...",
    "Pauses for audience applause, not a sausage",
    "Hold it up to the light --- not a brain in sight!",
    "Have a gorilla...",
    "There must be cure for it!",
    "There's a lot of it about, you know.",
    "You do that again and see what happens...",
    "Harm can come to a young lad like that!",
    "And with that remarks folks, the case of the Crown vs yourself was proven.",
    "Speak English you fool --- there are no subtitles in this scene.",
    "You gotta go owwwww!",
    "I have been called worse.",
    "It's only your word against mine.",
    "I think ... err ... I think ... I think I'll go home"
# end of insults from sudo source code
    )
    return $err_mesgs[$(Get-Random -Maximum $err_mesgs.Count)]
}