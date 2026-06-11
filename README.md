# Pangenomics_master_files_260610

This repository contains master files for testing and managing the PangenomiX Chip-based CNV analysis pipeline.

This repository is organized around `scripts/cnv_pipeline`.
It is used to manage PangenomiX CNV analysis scripts, prepare the APT-based command line analysis environment, and generate files that can be uploaded to Axiom Analysis Suite based on APT output.

Date: 2026.06.11
Author: Junho Lee

---

## 1. Repository Structure

The recommended directory structure is shown below.

```text
Pangenomics_master_files_260610/
├── Axiom_PangenomiX.r1/
├── apt_2.12.0_linux_64_x86_binaries.zip
├── apt_2.12.0_linux_64_x86_binaries/
├── scripts/
│   └── cnv_pipeline/
├── input/
│   └── axas_template_files/
│       ├── AxiomAnalysisSuiteData/
│       ├── CNData/
│       ├── Logs/
│       ├── QC/
│       ├── snpLists/
│       ├── Temp/
│       ├── AxiomGT1.calls.txt
│       ├── AxiomGT1.confidences.txt
│       ├── AxiomGT1.report.txt
│       ├── AxiomGT1.summary.a5
│       └── genotyping_cel_files
└── README.md
```

`apt_2.12.0_linux_64_x86_binaries.zip` is the downloaded APT package.
`apt_2.12.0_linux_64_x86_binaries/` is the extracted APT binary directory.

---

## 2. Purpose

This repository is used to organize the PangenomiX CNV analysis environment and to generate Axiom Analysis Suite upload-compatible files from APT-based command line analysis results.

The main purposes are:

* Management of PangenomiX CNV analysis scripts
* Organization of the APT-based command line analysis environment
* Generation of Axiom Analysis Suite upload files based on APT results

---

## 3. Required Software and Files

The following software and files are required to run the CNV pipeline.

```text
1. Axiom Analysis Suite
2. Axiom_PangenomiX.r1 library package
3. Analysis Power Tools
4. Output folder generated during or after an AxAS run
5. Demo CEL file or actual CEL file
```

Notes:

* CEL files are used when running analysis in Axiom Analysis Suite.
* It is recommended not to upload CEL files directly to the repository.
* The `Output` folder generated during or after an AxAS run should be copied into `input/axas_template_files/`.
* Before uploading files to a public repository, check whether sample names, specimen information, or internal analysis results are included.

---

## 4. Axiom Analysis Suite Download

Axiom Analysis Suite can be downloaded from the Thermo Fisher Scientific software download page.

```text
https://www.thermofisher.com/kr/ko/home/technical-resources/software-downloads.html
```

Download steps:

```text
1. Open the link above.
2. Click Axiom Analysis Suite 5.0.
3. Find the Axiom Analysis Suite 5.4 section.
4. Click Download now.
5. Install the software by following the Axiom Analysis Suite User Guide.
```

Axiom Analysis Suite 5.4 includes improved genotyping for difficult markers in multiplate batches.

If the library package includes remote copy number genotyping, AxAS Best Practices and Genotyping Analysis can also include remote copy number-related functions.

Recommended system requirements:

```text
Operating system: Microsoft Windows 10 64-bit Professional
CPU: Quad Core 2.83 GHz or higher
RAM: 32 GB recommended
C drive free space: At least 150 GB recommended
```

Note:

```text
Axiom Analysis Suite cannot be used to analyze Genome-Wide Human SNP Array 6.0 or other legacy Affymetrix genotyping arrays.
```

---

## 5. Axiom_PangenomiX.r1 Library Package

The `Axiom_PangenomiX.r1` library package is required for PangenomiX Chip CNV analysis.

This library package can be downloaded through Axiom Analysis Suite after installing the software.

### Download Steps

```text
1. Open Axiom Analysis Suite.
2. Go to the Preferences tab.
3. Find the NetAffx Library/Annotations section.
4. Click Update.
5. Find Axiom_PangenomiX.r1 in the Name column.
6. Confirm that the Array Type is Axiom_PangenomiX.
7. Check the Update? checkbox for the corresponding row.
8. Confirm that the checkbox is selected, then click OK.
9. After the library update is complete, check the folder path below.
```

Default Windows location:

```text
C:\Users\Public\Documents\AxiomAnalysisSuite\Library\Axiom_PangenomiX.r1
```

Copy this folder to the Linux server or analysis project directory.

Recommended location:

```text
Pangenomics_master_files_260610/Axiom_PangenomiX.r1/
```

---

## 6. Analysis Power Tools Download

Analysis Power Tools is required for APT-based command line analysis.

APT provides command line programs for analyzing GeneChip and Axiom array data.

Download page:

```text
https://www.thermofisher.com/kr/ko/home/technical-resources/software-downloads.html
```

Download steps:

```text
1. Open the link above.
2. Click Axiom Analysis Suite 5.0.
3. Scroll down to the Analysis Power Tools section.
4. Click Learn more.
5. Download the APT package from the redirected page.
```

Download file:

```text
apt_2.12.0_linux_64_x86_binaries.zip
```

File information:

```text
File name: apt_2.12.0_linux_64_x86_binaries.zip
File size: 200,411 KB
Checksum: 4da56954c7832b6855a4c8150f3a0913
```

Extract the package on the Linux server.

```bash
unzip apt_2.12.0_linux_64_x86_binaries.zip
```

Recommended location:

```text
Pangenomics_master_files_260610/apt_2.12.0_linux_64_x86_binaries/
```

---

## 7. Input Folder Preparation

The `input/axas_template_files/` folder should be prepared by copying files generated during an Axiom Analysis Suite run.

In Axiom Analysis Suite, upload a demo CEL file or actual CEL file and start the analysis run.

During or after the AxAS run, output files are generated in the following default path.

```text
C:\Users\Public\Documents\AxiomAnalysisSuite\Output
```

When a demo CEL file or actual CEL file is run, a folder similar to the following is created.

```text
C:\Users\Public\Documents\AxiomAnalysisSuite\Output\<Demo_CEL_file_or_actual_CEL_file_name>
```

`<Demo_CEL_file_or_actual_CEL_file_name>` is not a fixed folder name.
It depends on the demo CEL file, actual CEL file, or analysis name used in Axiom Analysis Suite.

Copy the files and folders from this AxAS Output folder into the following repository location.

```text
Pangenomics_master_files_260610/input/axas_template_files/
```

The final input structure should look like this.

```text
Pangenomics_master_files_260610/
└── input/
    └── axas_template_files/
        ├── AxiomAnalysisSuiteData/
        ├── CNData/
        ├── Logs/
        ├── QC/
        ├── snpLists/
        ├── Temp/
        ├── AxiomGT1.calls.txt
        ├── AxiomGT1.confidences.txt
        ├── AxiomGT1.report.txt
        ├── AxiomGT1.summary.a5
        └── genotyping_cel_files
```

The following four files are generated during the AxAS run and may be automatically removed after the analysis is completed.

```text
AxiomGT1.calls.txt
AxiomGT1.confidences.txt
AxiomGT1.report.txt
AxiomGT1.summary.a5
```

Therefore, copy these files during the run before they are deleted, and place them in `input/axas_template_files/`.

---

## 8. AxAS Output Folder Structure

The basic structure of the AxAS Output folder is shown below.

```text
C:\Users\Public\Documents\AxiomAnalysisSuite\Output\<Demo_CEL_file_or_actual_CEL_file_name>
├── AxiomAnalysisSuiteData/
├── CNData/
├── Logs/
├── QC/
├── snpLists/
├── Temp/
└── genotyping_cel_files
```

---

## 9. AxiomAnalysisSuiteData Folder

The `AxiomAnalysisSuiteData` folder contains AxAS analysis settings and sample-related information.

```text
AxiomAnalysisSuiteData/
├── cel_headers
├── AnalysisConfiguration.threshold_settings
├── AnalysisConfiguration.analysis_settings
├── Configuration
├── sample_info.bin
├── batch_info
└── user_colors.bin
```

Notes:

* `sample_info.bin` may contain sample-related information.
* Before uploading to a public GitHub repository, confirm whether internal sample information is included.

---

## 10. CNData Folder

The `CNData` folder contains CNV-related output files.

```text
CNData/
├── AxiomHMM.cnv.a5
└── AxiomHMM.report
```

Important file:

```text
AxiomHMM.cnv.a5
```

This file is very large and can be regenerated during analysis.

Therefore, after preparing the input example files, this file can be removed before uploading to GitHub.

```text
Pangenomics_master_files_260610/input/axas_template_files/CNData/AxiomHMM.cnv.a5
```

After removing `AxiomHMM.cnv.a5`, the remaining structure is:

```text
Pangenomics_master_files_260610/input/axas_template_files/CNData/
└── AxiomHMM.report
```

---

## 11. Logs Folder

The `Logs` folder contains AxAS and APT execution logs.

```text
Logs/
├── CopynumberAPT2
├── GenotypingAPT2
├── ParamCheck
├── AxiomWorkflowLog
├── DebugAxiomWorkflow
├── CopynumberAPT2.errors
└── ParamCheck.errors
```

These files can be used to check whether the analysis was completed successfully or to troubleshoot pipeline errors.

The log files generated by this pipeline may differ from those generated by AxAS.
However, differences in log files do not affect result viewing or analysis in Axiom Analysis Suite.

---

## 12. QC Folder

The `QC` folder may be generated but can be empty.

```text
QC/
```

GitHub does not track empty folders.
To keep this folder in the repository, add a `.gitkeep` file.

```bash
touch input/axas_template_files/QC/.gitkeep
```

---

## 13. snpLists Folder

The `snpLists` folder may also be generated but can be empty.

```text
snpLists/
```

To keep this folder in the repository, add a `.gitkeep` file.

```bash
touch input/axas_template_files/snpLists/.gitkeep
```

---

## 14. Temp Folder

The `Temp` folder contains temporary APT input-related files generated during AxAS analysis.

```text
Temp/
├── ChangedSCAxiom_PangenomiX.r1.apt-genotype-axiom.AxiomCN_GT1.apt2
├── Copynumber.APT2Input
└── GenoTyping.APT2Input
```

These files can be used as references to check the APT execution conditions used by AxAS.

---

## 15. CNV Pipeline Script

The CNV pipeline scripts are located in the following path.

```text
scripts/cnv_pipeline/
```

Before running the pipeline, check the current path and file structure.

```bash
cd /BiO/Pangenomics_master_files_260610
pwd
ls -lh
```

Check the script folder.

```bash
ls -lh scripts/cnv_pipeline
```

Grant execution permission to the shell scripts.

```bash
chmod +x scripts/cnv_pipeline/*.sh
```

---

## 16. Pipeline Execution

Example command:

```bash
cd /BiO/Pangenomics_master_files_260610
bash scripts/cnv_pipeline/run_master.sh <CEL_DIR> <RUN_NAME> [TEMPLATE_FILES_DIR]
```

Argument description:

```text
<CEL_DIR>
    Directory path containing the CEL files to be analyzed.

<RUN_NAME>
    Run name to be used for output files.
    Example: cnv_run_260611
    It is recommended to include the date at the end of the run name.

[TEMPLATE_FILES_DIR]
    Directory path of the input template files.
    This argument can be omitted if the current working directory is
    Pangenomics_master_files_260610 and the input files are located in the default path.
```

Default input template file location:

```text
Pangenomics_master_files_260610/input/axas_template_files/
```

Before running the pipeline, confirm the following items.

```text
1. Axiom_PangenomiX.r1 folder location
2. APT executable location
3. input/axas_template_files folder location
4. CEL file location
5. RUN_NAME setting
```

---

## 17. GitHub Upload Notes

Before uploading to GitHub, check the following file.

```text
input/axas_template_files/CNData/AxiomHMM.cnv.a5
```

`AxiomHMM.cnv.a5` is very large, so it is recommended to exclude or remove it before uploading to GitHub.

Example removal command:

```bash
rm -f input/axas_template_files/CNData/AxiomHMM.cnv.a5
```

Add `.gitkeep` files to keep empty folders.

```bash
touch input/axas_template_files/QC/.gitkeep
touch input/axas_template_files/snpLists/.gitkeep
```

Example GitHub upload commands:

```bash
git status

git add README.md
git add scripts/cnv_pipeline/
git add input/axas_template_files/

git commit -m "Add PangenomiX CNV pipeline files"
git push origin main
```

Before uploading to a public repository, carefully check the following files.

```text
sample_info.bin
genotyping_cel_files
*.CEL
AxiomHMM.cnv.a5
Internal confidential files
Files containing actual sample names or personal information
```

---

## 18. Notes

This repository is intended for organizing and testing the PangenomiX Chip CNV analysis pipeline.

Axiom Analysis Suite, APT, and the Axiom_PangenomiX.r1 library package are software and library resources provided by Thermo Fisher Scientific.

Before using or redistributing these files, confirm the relevant usage rights and redistribution permissions.

---

## Author

Junho Lee
