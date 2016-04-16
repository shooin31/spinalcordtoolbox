#!/bin/bash
#
# Example of commands to process multi-parametric data of the spinal cord
# For information about acquisition parameters, see: https://dl.dropboxusercontent.com/u/20592661/publications/Fonov_NIMG14_MNI-Poly-AMU.pdf
# N.B. The parameters are set for these type of data. With your data, parameters might be slightly different.
#
# To run without fslview output, type:
#   ./batch_processing.sh -nodisplay
#
# tested with dev on 2016-04-15 at 12.15

# Check if display is on or off
if [[ $@ == *"-nodisplay"* ]]; then
  DISPLAY=false
  echo "Display mode turned off."
else
  DISPLAY=true
fi

# get SCT_DIR
source sct_env

# download example data (errsm_30)
sct_download_data -d sct_example_data

# display starting time:
echo "Started at: $(date +%x_%r)"

# go in folder
cd sct_example_data

# t2
# ===========================================================================================
cd t2
# spinal cord segmentation
sct_propseg -i t2.nii.gz -c t2
# check your results:
if [ $DISPLAY = true ]; then
  fslview t2 -b 0,800 t2_seg -l Red -t 0.5 &
fi
# vertebral labeling. Here we use the fact that the FOV is centered at C7.
sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -initcenter 7
# create labels at C3 and T2 vertebral levels
sct_label_utils -i t2_seg_labeled.nii.gz -p label-vertebrae -vert 3,9
# register to template
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -l labels.nii.gz
# warp template without the white matter atlas (we don't need it)
sct_warp_template -d t2.nii.gz -w warp_template2anat.nii.gz -a 0
# check results
if [ $DISPLAY = true ]; then
  fslview t2.nii.gz -b 0,800 label/template/MNI-Poly-AMU_T2.nii.gz -b 0,4000 label/template/MNI-Poly-AMU_level.nii.gz -l MGH-Cortical -t 0.5 label/template/MNI-Poly-AMU_GM.nii.gz -l Red-Yellow -b 0.5,1 label/template/MNI-Poly-AMU_WM.nii.gz -l Blue-Lightblue -b 0.5,1 &
fi
# compute average cross-sectional area and volume between C3 and C4 levels
sct_process_segmentation -i t2_seg.nii.gz -p csa -vert 3:4 -o t2
# --> Mean CSA: 77.2454304712 +/- 2.02667261843 mm^2
# --> Volume (in volume.txt): 2319.0 mm^3

# go back to root folder
cd ..


#  t1
# ----------
cd t1
# spinal cord segmentation
sct_propseg -i t1.nii.gz -c t1
# check results
if [ $DISPLAY = true ]; then
  fslview t1 -b 0,800 t1_seg -l Red -t 0.5 &
fi
# create mask around spinal cord (for cropping)
sct_create_mask -i t1.nii.gz -p centerline,t1_seg.nii.gz -size 61 -f box -o mask_t1.nii.gz
# crop t1 and t1_seg (for faster registration)
sct_crop_image -i t1.nii.gz -m mask_t1.nii.gz -o t1_crop.nii.gz
sct_crop_image -i t1_seg.nii.gz -m mask_t1.nii.gz -o t1_seg_crop.nii.gz
# register to template (which was previously registered to the t2).
sct_register_multimodal -i ../t2/label/template/MNI-Poly-AMU_T2.nii.gz -iseg ../t2/label/template/MNI-Poly-AMU_cord.nii.gz -d t1_crop.nii.gz -dseg t1_seg_crop.nii.gz -param step=1,type=seg,algo=slicereg,metric=MeanSquares:step=2,type=im,algo=syn,iter=3,gradStep=0.2,metric=CC
# concatenate transformations
sct_concat_transfo -w ../t2/warp_template2anat.nii.gz,warp_MNI-Poly-AMU_T22t1_crop.nii.gz -d t1.nii.gz -o warp_template2t1.nii.gz
sct_concat_transfo -w warp_t1_crop2MNI-Poly-AMU_T2.nii.gz,../t2/warp_anat2template.nii.gz -d $SCT_DIR/data/template/MNI-Poly-AMU_T2.nii.gz -o warp_t12template.nii.gz
# warp template
sct_warp_template -d t1.nii.gz -w warp_template2t1.nii.gz -a 0
# check results
if [ $DISPLAY = true ]; then
  fslview t1.nii.gz label/template/MNI-Poly-AMU_T2.nii.gz -b 0,4000 label/template/MNI-Poly-AMU_level.nii.gz -l MGH-Cortical -t 0.5 label/template/MNI-Poly-AMU_GM.nii.gz -l Red-Yellow -b 0.5,1 label/template/MNI-Poly-AMU_WM.nii.gz -l Blue-Lightblue -b 0.5,1 &
fi
# warp T1 to template space
sct_apply_transfo -i t1.nii.gz -d $SCT_DIR/data/template/MNI-Poly-AMU_T2.nii.gz -w warp_t12template.nii.gz
# check registration of T1 to template
if [ $DISPLAY = true ]; then
  fslview $SCT_DIR/data/template/MNI-Poly-AMU_T2.nii.gz -b 0,4000 t1_reg.nii.gz -b 0,800 &
fi
cd ..


# mt
# ----------
cd mt
# bring T2 segmentation in MT space to help segmentation (no optimization)
sct_register_multimodal -i ../t2/t2_seg.nii.gz -d mt1.nii.gz -identity 1 -x nn
# segment mt1
sct_propseg -i mt1.nii.gz -c t2 -init-centerline t2_seg_reg.nii.gz
# check results
if [ $DISPLAY = true ]; then
   fslview mt1 -b 0,800 mt1_seg.nii.gz -l Red -t 0.5 &
fi
# create mask around spinal cord (for faster processing)
sct_create_mask -i mt1.nii.gz -p centerline,mt1_seg.nii.gz -size 51 -f box -o mask_mt1.nii.gz
# crop data
sct_crop_image -i mt1.nii.gz -m mask_mt1.nii.gz -o mt1_crop.nii.gz
sct_crop_image -i mt1_seg.nii.gz -m mask_mt1.nii.gz -o mt1_seg_crop.nii.gz
# create close mask around spinal cord (for more accurate registration results)
sct_create_mask -i mt1_crop.nii.gz -p centerline,mt1_seg_crop.nii.gz -size 31 -f cylinder -o mask_mt1_crop.nii.gz
# register mt0 on mt1
# tips: here we only use rigid transformation because both images have very similar sequence parameters. We don't want to use SyN/BSplineSyN to avoid introducing spurious deformations.
sct_register_multimodal -i mt0.nii.gz -d mt1_crop.nii.gz -param step=1,type=im,algo=rigid,slicewise=1,metric=CC -m mask_mt1_crop.nii.gz -x spline
# compute mtr
sct_compute_mtr -mt0 mt0_reg.nii.gz -mt1 mt1_crop.nii.gz
# register template (in T2 space) to mt1
# Tips: here we only use the segmentations due to poor SC/CSF contrast at the bottom slice.
# Tips: First step: rigid based on images, with moderate smoothing, to capture global rotations for each slice (e.g., if patient turned his head), then at second step: slicereg based on segmentations, in order to match the center of mass of the spinal cord between subject and template.
sct_register_multimodal -i ../t2/template2anat.nii.gz -d mt1_crop.nii.gz -iseg ../t2/label/template/MNI-Poly-AMU_cord.nii.gz -dseg mt1_seg_crop.nii.gz -param step=1,type=im,algo=rigid,slicewise=1,metric=CC,smooth=3:step=2,type=seg,algo=slicereg,smooth=5
# concat transfo
sct_concat_transfo -w ../t2/warp_template2anat.nii.gz,warp_template2anat2mt1_crop.nii.gz -d mtr.nii.gz -o warp_template2mt.nii.gz
# warp template (to get vertebral labeling)
sct_warp_template -d mt1_crop.nii.gz -w warp_template2mt.nii.gz
# check registration result
if [ $DISPLAY = true ]; then
   fslview mtr.nii.gz -b 0,100 mt0mt1.nii.gz -b 0,1200 label/template/MNI-Poly-AMU_T2.nii.gz -b 0,4000 label/template/MNI-Poly-AMU_level.nii.gz -l MGH-Cortical -t 0.5 label/template/MNI-Poly-AMU_GM.nii.gz -l Red-Yellow -b 0.3,1 label/template/MNI-Poly-AMU_WM.nii.gz -l Blue-Lightblue -b 0.3,1 &
fi
# extract MTR within the white matter
sct_extract_metric -i mtr.nii.gz -method map -o mtr_in_wm_without_gmreg -l 33
# OPTIONAL PART: SEGMENT GRAY MATTER:
# <<<<<<<<<<
# add mt1 and mt0 to increase GM/WM contrast
sct_maths -i mt0_reg.nii.gz -add mt1_crop.nii.gz -o mt0mt1.nii.gz
# segment WM/GM
sct_segment_graymatter -i mt0mt1.nii.gz -s mt1_seg_crop.nii.gz
# register WM/GM template to WM/GM seg
sct_register_graymatter -gm mt0mt1_gmseg.nii.gz -wm mt0mt1_wmseg.nii.gz -w warp_template2mt.nii.gz
# warp template (this time corrected for internal structure)
sct_warp_template -d mt1_crop.nii.gz -w warp_template2mt0mt1_gmseg.nii.gz
# check registration result
if [ $DISPLAY = true ]; then
   fslview mtr.nii.gz -b 0,100 mt0mt1.nii.gz -b 0,1200 label/template/MNI-Poly-AMU_T2.nii.gz -b 0,4000 label/template/MNI-Poly-AMU_level.nii.gz -l MGH-Cortical -t 0.5 label/template/MNI-Poly-AMU_GM.nii.gz -l Red-Yellow -b 0.3,1 label/template/MNI-Poly-AMU_WM.nii.gz -l Blue-Lightblue -b 0.3,1 &
fi
# >>>>>>>>>>
# extract MTR within the white matter
sct_extract_metric -i mtr.nii.gz -method map -o mtr_in_wm_with_gmreg -l 33
# Once we have register the WM atlas to the subject, we can compute the cross-sectional area (CSA) of specific pathways.
# For example, we can compare the CSA of the left corticospinal tract (CST) to the right CST averaged across the vertebral levels C2 to C5:
sct_process_segmentation -i label/atlas/WMtract__02.nii.gz -p csa -vert 2:5 -o mt_cst_left_
# --> Mean CSA of left CST: 5.44513005315 +/- 0.634018309407 mm^2
sct_process_segmentation -i label/atlas/WMtract__17.nii.gz -p csa -vert 2:5 -o mt_cst_right_
# --> Mean CSA of right CST: 5.42871286128 +/- 0.461070598388 mm^2
# Get CSA of the left dorsal column (fasciculus cuneatus + fasciculus gracilis)
sct_maths -i label/atlas/WMtract__00.nii.gz -add label/atlas/WMtract__01.nii.gz -o left_dorsal_column.nii.gz
sct_process_segmentation -i left_dorsal_column.nii.gz -p csa -l 2:5 -t label/template/MNI-Poly-AMU_level.nii.gz -o mt_cst_dorsal_
# --> Mean CSA of the left dorsal column: 11.26572434 +/- 0.785786800121 mm^2
cd ..


# dmri
# ----------
cd dmri
sct_maths -i dmri.nii.gz -mean t -o dmri_mean.nii.gz
# bring T2 segmentation in dmri space to create mask (no optimization)
sct_register_multimodal -i ../t2/t2_seg.nii.gz -d dmri_mean.nii.gz -identity 1 -x nn
# create mask to help moco and for faster processing
sct_create_mask -i dmri_mean.nii.gz -p centerline,t2_seg_reg.nii.gz -size 51 -f cylinder
# crop data
sct_crop_image -i dmri.nii.gz -m mask_dmri_mean.nii.gz -o dmri_crop.nii.gz
# motion correction
sct_dmri_moco -i dmri_crop.nii.gz -bvec bvecs.txt -x spline
# segmentation with propseg
sct_propseg -i dwi_moco_mean.nii.gz -c t1 -init-centerline t2_seg_reg.nii.gz
# check segmentation
if [ $DISPLAY = true ]; then
  fslview dwi_moco_mean -b 0,300 dwi_moco_mean_seg -l Red -t 0.5 &
fi
# register template to dwi
# Tips: We use the template registered to the MT data in order to account for gray matter segmentation
# Tips: again, here, we prefer no stick to rigid registration on segmentation following by slicereg to realign center of mass. If there are susceptibility distortions in your EPI, then you might consider adding a third step with bsplinesyn or syn transformation for local adjustment.
sct_register_multimodal -i ../mt/label/template/MNI-Poly-AMU_T2.nii.gz -d dwi_moco_mean.nii.gz -iseg ../mt/label/template/MNI-Poly-AMU_cord.nii.gz -dseg dwi_moco_mean_seg.nii.gz -param step=1,type=seg,algo=rigid,slicewise=1,smooth=5,iter=50:step=2,type=seg,algo=slicereg,smooth=5
# concatenate transfo: (1) template -> anat -> MT -> MT_gmreg ; (2) MT_gmreg -> DWI
sct_concat_transfo -w ../mt/warp_template2mt0mt1_gmseg.nii.gz,warp_MNI-Poly-AMU_T22dwi_moco_mean.nii.gz -d dwi_moco_mean.nii.gz -o warp_template2dmri.nii.gz
# warp template and white matter atlas
sct_warp_template -d dwi_moco_mean.nii.gz -w warp_template2dmri.nii.gz
# visualize white matter template and lateral CST on DWI
if [ $DISPLAY = true ]; then
  fslview dwi_moco_mean -b 0,300 label/template/MNI-Poly-AMU_WM.nii.gz -l Blue-Lightblue -b 0.2,1 -t 0.5 label/atlas/WMtract__02.nii.gz -b 0.2,1 -l Red label/atlas/WMtract__17.nii.gz -b 0.2,1 -l Yellow &
fi
# compute DTI metrics
# Tips: the flag -method "restore" allows you to estimate the tensor with robust fit (see help)
sct_dmri_compute_dti -i dmri_crop_moco.nii.gz -bval bvals.txt -bvec bvecs.txt
# compute FA within right and left lateral corticospinal tracts from slices 1 to 3 using maximum a posteriori
sct_extract_metric -i dti_FA.nii.gz -z 1:3 -method map -l 2,17 -o fa_in_cst
cd ..


# fmri
# ----------
cd fmri
# create mask at the center of the FOV (will be used for moco)
sct_create_mask -i fmri.nii.gz -p center -size 30 -f cylinder
# moco
sct_fmri_moco -i fmri.nii.gz -m mask_fmri.nii.gz
# tips: if you have low SNR you can group consecutive images with "-g"
# put T2 segmentation into fmri space
sct_register_multimodal -i ../t2/t2_seg.nii.gz -d fmri_moco_mean.nii.gz -identity 1 -x nn
# extract centerline
sct_process_segmentation -i t2_seg_reg.nii.gz -p centerline
# segment mean fMRI volume
# tips: we use the T2 segmentation to help with fMRI segmentation
# tips: we use "-radius 5" otherwise the segmentation is too small
# tips: we use "-max-deformation 4" to prevent the propagation from stopping at the edge
sct_propseg -i fmri_moco_mean.nii.gz -c t2 -init-centerline t2_seg_reg_centerline.nii.gz -radius 5 -max-deformation 4
# check segmentation
if [ $DISPLAY = true ]; then
  fslview fmri_moco_mean -b 0,1000 fmri_moco_mean_seg -l Red -t 0.5 &
fi
# here segmentation slightly failed due to the close proximity of susceptibility artifact --> use file "fmri_moco_mean_seg_modif.nii.gz"
# register template to fmri: here we use the template register to the MT to get the correction of the internal structure
sct_register_multimodal -i ../mt/label/template/MNI-Poly-AMU_T2.nii.gz -d fmri_moco_mean.nii.gz -iseg ../mt/label/template/MNI-Poly-AMU_cord.nii.gz -dseg fmri_moco_mean_seg_modif.nii.gz -param step=1,type=seg,algo=slicereg,metric=MeanSquares,smooth=2:step=2,type=im,algo=bsplinesyn,metric=MeanSquares,iter=5,gradStep=0.5
# concatenate transfo: (1) template -> anat -> MT -> MT_gm ; (2) MT_gm -> fmri
sct_concat_transfo -w ../mt/warp_template2mt0mt1_gmseg.nii.gz,warp_MNI-Poly-AMU_T22fmri_moco_mean.nii.gz -d fmri_moco_mean.nii.gz -o warp_template2fmri.nii.gz
# warp template and spinal levels (here we don't need the WM atlas)
sct_warp_template -d fmri_moco_mean.nii.gz -w warp_template2fmri.nii.gz -a 0 -s 1
# check results
if [ $DISPLAY = true ]; then
  fslview fmri_moco_mean -b 0,1300 label/spinal_levels/spinal_level_C3.nii.gz -l Red -b 0,0.05 label/spinal_levels/spinal_level_C4.nii.gz -l Blue -b 0,0.05 label/spinal_levels/spinal_level_C5.nii.gz -l Green -b 0,0.05 label/spinal_levels/spinal_level_C6.nii.gz -l Yellow -b 0,0.05 label/spinal_levels/spinal_level_C7.nii.gz -l Pink -b 0,0.05 &
fi
cd ..


# display results (to easily compare integrity across SCT versions)
# ----------
echo "t2/CSA: " `grep -v '^#' t2/csa_mean.txt | grep -v '^$'`
echo "mt/MTR: " `grep -v '^#' mt/mtr_in_wm_without_gmreg.txt | grep -v '^$'`
echo "mt/MTR: " `grep -v '^#' mt/mtr_in_wm_with_gmreg.txt | grep -v '^$'`
echo "mt/CSA: " `grep -v '^#' mt/mt_cst_dorsal_csa_mean.txt | grep -v '^$'`
echo "dmri/FA:" `grep -v '^#' dmri/fa_in_cst.txt | grep -v '^$' | grep -v '^2'`
echo "dmri/FA:" `grep -v '^#' dmri/fa_in_cst.txt | grep -v '^$' | grep -v '^17'`

# fMRI results: https://dl.dropboxusercontent.com/u/20592661/sct/result_batch_processing_fmri.png
# display ending time:
echo "Ended at: $(date +%x_%r)"
