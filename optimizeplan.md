# Optimization plan
## This plan is to make the code much faster
In @code/zigbpe.zig the main loop begins by looping over the pairs and counting them.
What I want to do is pull that out of the loop and do it at the start.
In addition I want to use a zig priority_queue to track the pairs with the highest counts.

The change the rest of the loop to pull the most frequent pair and merge it.

This will reduce the number of iterations of the main loop and make it much faster.

## Progress tracker
[ ] Pull the pair counting out of the main loop
[ ] Use a priority queue to track the most frequent pairs
[ ] Change the main loop to pull the most frequent pair and merge it
[ ] Ensure the code still builds and runs



