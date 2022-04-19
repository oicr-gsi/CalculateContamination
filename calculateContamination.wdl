version 1.0

import "imports/pull_bwaMem.wdl" as bwaMem

struct InputGroup {
    File fastq1
    File fastq2
    String readGroups
}

struct BamInputs {
    File bamFile
    File baiFile
}

workflow calculateContamination {
    input {
        Array[InputGroup]? inputGroups
        Array[BamInputs]? bamFiles
        String inputType
    }

    parameter_meta {
    }
 
    meta {
        author: "Murto Hilali"
        email: "mhilali@oicr.on.ca"
        description: "QC workflow to determine contamination metrics on tumor bam files."
        dependencies: [
            {
                name: "gatk/4.2.0.0",
                url: "https://gatk.broadinstitute.org"
            },
            {
                name: "hg38-gatk-gnomad/2.0",
                url: "https://gnomad.broadinstitute.org/"
            }
        ]
        output_meta: {
            contaminationMetrics: "Metrics about contamination for inputs bams/fastqs"

        }
    }

# =======================================================
#   Accept fastqs and align them into bam files.
#   Bam and index file(s) collected into a new array.
# =======================================================

    if ( inputType=="fastq" && defined(inputGroups) ){
        Array[InputGroup] inputGroups_ = select_first([inputGroups])
        scatter (ig in inputGroups_) {
            call bwaMem.bwaMem {
                input:
                    fastqR1 = ig.fastq1,
                    fastqR2 = ig.fastq2,
                    readGroups = ig.readGroups
            }
            BamInputs indexedBamFiles = {
                "bamFile":bwaMem.bwaMemBam,
                "baiFile":bwaMem.bwaMemIndex
            }
        }
    }

# =======================================================
#   Check to see if bam files array has 1 or 2 files.
#   Determines whether we run tumor/normal or tumor-only.
# =======================================================

    Array[BamInputs] bamFiles_ = select_first([bamFiles, indexedBamFiles])    
    
    if ( length(bamFiles_)==1 ) {
        call tumorOnlyMetrics {
            input:
                tumorBamFile = bamFiles_[0].bamFile,
                tumorBaiFile = bamFiles_[0].baiFile
        }
    }
    if ( length(bamFiles_)==2 ) {
        call getMetrics {
            input:
                tumorBamFile = bamFiles_[0].bamFile,
                tumorBaiFile = bamFiles_[0].baiFile,
                normalBamFile = bamFiles_[1].bamFile,
                normalBaiFile = bamFiles_[1].baiFile
        }
    }

    output {
        File contaminationMetrics = select_first([tumorOnlyMetrics.tumorContaminationTable, getMetrics.pairContaminationTable])
    }
}


task getMetrics{
    input {
        File normalBamFile
        File normalBaiFile
        File tumorBamFile
        File tumorBaiFile
        String refVCF = "$HG38_GATK_GNOMAD_ROOT/small_exac_common_3.hg38.vcf.gz"
        
        String modules = "gatk/4.2.0.0 hg38-gatk-gnomad/2.0"
        Int memory = 24
        Int timeout = 12
    }

    parameter_meta {
        modules: "Required environment modules"
        memory: "Memory allocated for this job"
        timeout: "Time in hours before task timeout"
    }

    command <<<
module unload cromwell #temp for local testing
module unload java     #temp for local testing
module load ~{modules}

mv ~{tumorBamFile} ./tumorBamFile.bam
mv ~{tumorBaiFile} ./tumorBamFile.bam.bai

mv ~{normalBamFile} ./normalBamFile.bam
mv ~{normalBaiFile} ./normalBamFile.bam.bai

gatk GetPileupSummaries \
-I tumorBamFile.bam \
-V ~{refVCF} \
-L ~{refVCF} \
-O tumor.summaries.table

gatk GetPileupSummaries \
-I normalBamFile.bam \
-V ~{refVCF} \
-L ~{refVCF} \
-O normal.summaries.table

gatk CalculateContamination \
-I tumor.summaries.table \
-matched normal.summaries.table \
-O contamination.table

    >>>

    runtime {
        modules: "~{modules}"
        memory: "~{memory}G"
        timeout: "~{timeout}"
    }

    output {
        File pairContaminationTable = "contamination.table"
    }

    meta {
        output_meta: {
            pairContaminationTable: "Table containing contamination metrics for T/N pair"

        }
    }
}

task tumorOnlyMetrics{
    input {
        File tumorBamFile
        File tumorBaiFile
        String modules = "gatk/4.2.0.0 hg38-gatk-gnomad/2.0"
        String refVCF = "$HG38_GATK_GNOMAD_ROOT/small_exac_common_3.hg38.vcf.gz"
        Int memory = 24
        Int timeout = 12
    }

    parameter_meta {
        modules: "Required environment modules"
        memory: "Memory allocated for this job"
        timeout: "Time in hours before task timeout"
    }

    command <<<
module unload cromwell #temp for local testing
module unload java     #temp for local testing
module load ~{modules}

mv ~{tumorBamFile} ./tumorBamFile.bam
mv ~{tumorBaiFile} ./tumorBamFile.bam.bai

gatk GetPileupSummaries \
-I tumorBamFile.bam \
-V ~{refVCF} \
-L ~{refVCF} \
-O tumor.summaries.table

gatk CalculateContamination \
-I tumor.summaries.table \
-O contamination.table

    >>>

        runtime {
            modules: "~{modules}"
            memory: "~{memory}G"
            timeout: "~{timeout}"
        }

        output {
            File tumorContaminationTable = "contamination.table"
        }

        meta {
            output_meta: {
                tumorContaminationTable: "Table containing tumor bam contamination metrics"

            }
        }
}