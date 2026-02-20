---
license: apache-2.0
pipeline_tag: mask-generation
library_name: coreml
---

# SAM 2.1 Small Core ML

SAM 2 (Segment Anything in Images and Videos), is a collection of foundation models from FAIR that aim to solve promptable visual segmentation in images and videos. See the [SAM 2 paper](https://arxiv.org/abs/2408.00714) for more information.

This is the Core ML version of [SAM 2.1 Small](https://huggingface.co/facebook/sam2.1-hiera-small), and is suitable for use with the [SAM2 Studio demo app](https://github.com/huggingface/sam2-studio). It was converted in `float16` precision using [this fork](https://github.com/huggingface/segment-anything-2/tree/coreml-conversion) of the original code repository.

## Download

Install `huggingface-cli`

```bash
brew install huggingface-cli
```

```bash
huggingface-cli download --local-dir models apple/coreml-sam2.1-small
```

## Citation

To cite the paper, model, or software, please use the below:
```
@article{ravi2024sam2,
  title={SAM 2: Segment Anything in Images and Videos},
  author={Ravi, Nikhila and Gabeur, Valentin and Hu, Yuan-Ting and Hu, Ronghang and Ryali, Chaitanya and Ma, Tengyu and Khedr, Haitham and R{\"a}dle, Roman and Rolland, Chloe and Gustafson, Laura and Mintun, Eric and Pan, Junting and Alwala, Kalyan Vasudev and Carion, Nicolas and Wu, Chao-Yuan and Girshick, Ross and Doll{\'a}r, Piotr and Feichtenhofer, Christoph},
  journal={arXiv preprint arXiv:2408.00714},
  url={https://arxiv.org/abs/2408.00714},
  year={2024}
}
```
