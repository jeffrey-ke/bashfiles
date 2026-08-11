#!/bin/bash

echo "you're in tesu!"

export DATA=/data/user/jeffk
setxkbmap -option caps:escape

# .local/bin is prepended by .bash_tools; these two are tesu-only trees.
export PATH=$HOME/nvim-linux-x86_64/bin:$PATH
export PATH=$HOME/isaacsim:$PATH

# >>> path registry >>>
export mpdata='/data/user/jeffk/datasets/mixed-persp'
export segroot='/home/jeffk/repo/segmentation'
export vyaml='/home/jeffk/repo/segmentation/src/segmentation/verifier/configs'
export ycb_obj='/home/jeffk/repo/isaac_datagen/datasets/ycb_dataset'
export assets='/home/jeffk/repo/isaac_datagen/assets'
export datasets='/data/user/jeffk/datasets'
export isgen='/home/jeffk/repo/isaac_datagen'
export propconf='/home/jeffk/repo/reference_matching/src/reference_matching/configs'
export data='/data/user/jeffk'
export sbp='/data/user/jeffk/seg_benchmark_predictions'
export runs='/home/jeffk/repo/refseg-workspace/segmentation/runs'
export rback='/data/user/jeffk/random_backgrounds'
export segruns='/data/user/jeffk/segmentation_runs'
export n10n='/data/user/jeffk/n-10n'
export n10nfullstore='/data/user/jeffk/n-10n/3-30/full-store-only'
export jlgsf='/data/user/jeffk/n-10n/jittered-log-scaled-flat-fixed'
# <<< path registry <<<
