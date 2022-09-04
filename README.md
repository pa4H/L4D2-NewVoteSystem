# [L4D2] New vote system

The voting system is written from scratch.

Plugin allows you to:
1. Create custom votes: sm_customVote <VoteText> <PassVoteText>
2. Vote for kick a player from another team.
3. Vote for killing infected bots: __!killbots__, __!kb__.
4. Vote for kick of spectators: __!kickspec__, __!ks__, __!sk__, __!nospec__, __!speckick__.
5. Ability to use the __!rematch__ command. (Just start RestartChapter vote)
  
Fixed a game bug when 60% of votes are not pass the vote. (VALVe, did you skip math lessions?)

Plugin disable "Return to Lobby".

Fixed game bug "Voting is already started".
  
## FAQ:
```
  Q: Why player who created the vote not vote "Yes" automatically?
  A: It might be for trolling. If an inattentive player votes "YES" when the vote for kick his.
  
  Q: Why plugin allow to votekick players from another team
  A: This is a game bug that has existed since the release. I'm not going to change the established mechanics of the game.
  
  Q: Map change not working!
  A: Did you forget about l4d2_changelevel.smx? Put it in your plugins folder.
 ```
 
[Developer](https://vk.com/pa4h1337)
