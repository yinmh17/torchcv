#!/usr/bin/env bash

# check the enviroment info
nvidia-smi
PYTHON="python -u"

WORK_DIR=$(cd $(dirname $0)/../../../;pwd)
export PYTHONPATH=${WORK_DIR}:${PYTHONPATH}
cd ${WORK_DIR}

DATA_DIR="/data/home/v-miyin/ADE20K"

BACKBONE="deepbase_resnet101_dilated8"
MODEL_NAME="nonlocalbn"
CHECKPOINTS_NAME="fs_res101_nonlocalbn_ade20k_seg_trainval"$2
PRETRAINED_MODEL="./pretrained_models/3x3resnet101-imagenet.pth"

CONFIG_FILE='configs/seg/ade20k/NL_fcn_ade20k_seg.conf'
#MAX_ITERS=150000
MAX_ITERS=75000
LOSS_TYPE="dsnohemce_loss"
BASE_LR=0.002

LOG_DIR="./log/seg/ade20k/"
LOG_FILE="${LOG_DIR}${CHECKPOINTS_NAME}.log"

if [[ ! -d ${LOG_DIR} ]]; then
    echo ${LOG_DIR}" not exists!!!"
    mkdir -p ${LOG_DIR}
fi

export NCCL_LL_THRESHOLD=0
#export NCCL_TREE_THRESHOLD=0

NGPUS=8
DIST_PYTHON="${PYTHON} -m torch.distributed.launch --nproc_per_node=${NGPUS}"

if [[ "$1"x == "train"x ]]; then
  ${DIST_PYTHON} main.py --config_file ${CONFIG_FILE} --phase train --train_batch_size 2 --val_batch_size 1 \
                         --backbone ${BACKBONE} --model_name ${MODEL_NAME} --gpu 0 1 2 3 4 5 6 7 --drop_last y --syncbn y --dist y \
                         --data_dir ${DATA_DIR} --loss_type ${LOSS_TYPE} --max_iters ${MAX_ITERS} --base_lr ${BASE_LR} --max_iters ${MAX_ITERS}\
                         --checkpoints_name ${CHECKPOINTS_NAME} --resume ./pretrained_models/fs_res101_nonlocal_ade20k_segtag_latest.pth 2>&1 | tee ${LOG_FILE}

elif [[ "$1"x == "resume"x ]]; then
  ${DIST_PYTHON} main.py --config_file ${CONFIG_FILE} --phase train --train_batch_size 2 --val_batch_size 1 \
                         --backbone ${BACKBONE} --model_name ${MODEL_NAME} --drop_last y --syncbn y --dist y \
                         --data_dir ${DATA_DIR} --loss_type ${LOSS_TYPE} --max_iters ${MAX_ITERS} \
                         --resume_continue y --resume ./checkpoints/seg/ade20k/${CHECKPOINTS_NAME}_latest.pth \
                         --checkpoints_name ${CHECKPOINTS_NAME} --pretrained ${PRETRAINED_MODEL}  2>&1 | tee -a ${LOG_FILE}

elif [[ "$1"x == "val"x ]]; then
  ${PYTHON} main.py --config_file ${CONFIG_FILE} --phase test --gpu 0 1 2 3 4 5 6 7 --gather n \
                    --backbone ${BACKBONE} --model_name ${MODEL_NAME} --checkpoints_name ${CHECKPOINTS_NAME} \
                    --resume ./checkpoints/seg/ade20k/${CHECKPOINTS_NAME}_latest.pth  --resume_strict y\
                    --test_dir ${DATA_DIR}/val/image --out_dir val  2>&1 | tee -a ${LOG_FILE}
  cd metric/seg/
  ${PYTHON} seg_evaluator.py --config_file "../../"${CONFIG_FILE} \
                             --pred_dir ../../results/seg/ade20k/${CHECKPOINTS_NAME}/val/label \
                             --gt_dir ${DATA_DIR}/val/label  2>&1 | tee -a "../../"${LOG_FILE}

elif [[ "$1"x == "test"x ]]; then
  ${PYTHON} main.py --config_file ${CONFIG_FILE} --phase test --gpu 0 1 2 3 --gather n \
                    --backbone ${BACKBONE} --model_name ${MODEL_NAME} --checkpoints_name ${CHECKPOINTS_NAME} \
                    --resume ./checkpoints/seg/ade20k/${CHECKPOINTS_NAME}_latest.pth \
                    --test_dir ${DATA_DIR}/test --out_dir test  2>&1 | tee -a ${LOG_FILE}

else
  echo "$1"x" is invalid..."
fi
