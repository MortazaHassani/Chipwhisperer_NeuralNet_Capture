# CW305 MNIST Neural Network Target

This project implements a fully connected neural network (784 -> 64 -> 64 -> 32 -> 10) on the ChipWhisperer CW305 FPGA board.

## Structure

- `cw305_mnist_nn.ipynb`: Jupyter notebook for data loading, FPGA communication, and power trace capture.
- `test2.srcs/sources_1/new/`: Verilog source files.
  - `cw305_top.v`: Top-level module with USB register interface.
  - `neural_network.v`: NN controller and layer instantiations.
  - `matrix_multiply.v`, `relu.v`, `argmax.v`: NN components.
  - `image_memory.v`: Writable RAM for input image.
  - `matrix*.v`: Synchronous BRAM for pre-trained weights.
- `mem/`: Pre-trained weight files (`.mif` hex format).
- `MNIST-10000-784.csv`: MNIST dataset for testing.

## How to Build

1. Open Vivado and create a new project targeting Artix-7 100T (part `xc7a100tftg256-2`).
2. Add all `.v` files from `test2.srcs/sources_1/new/` to the project.
3. Add `cw305.xdc` from `test2.srcs/constrs_1/new/` as a constraint.
4. Add all `.mif` files to the project as "Data Files" or ensure they are in the same directory as the source files.
5. Run Synthesis, Implementation, and Generate Bitstream.

## How to Run

1. Connect the CW305 and CW-Lite boards.
2. Open `cw305_mnist_nn.ipynb` in Jupyter.
3. Update `BITFILE` path if necessary.
4. Run all cells to program the FPGA, load an image, and capture a power trace.

## Register Map

| Address (Hex) | Name | Direction | Description |
|---|---|---|---|
| `0x0000` - `0x030F` | `IMAGE_MEM` | Write | Input image pixels (784 bytes) |
| `0x1000` | `REG_NN_GO` | Write | Write 1 to start NN classification |
| `0x1001` | `REG_NN_RESULT`| Read | Classification result (0-9) |
| `0x1002` | `REG_NN_DONE` | Read | 1 if classification is complete |
| `0x1003` | `REG_USER_LED` | Write | Control onboard LEDs |
| `0x1004` | `REG_NN_STATE` | Read | Internal NN state machine status |
