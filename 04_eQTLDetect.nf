nextflow.enable.dsl=2

/*   ------------ eQTL Nextflow pipeline script04: Performs cis and trans QTL mapping using the RNA seq and corresponding WGS data ----------------- */


/*           ****************** NOTE ******************                           */
/* Take care of input and output paths before running the script                  */


                                /* INPUT */
/**  --Input: Gene, transcript count matrices and splicing covariates -- **/ 

params.phenotype_GeneCount = "$projectDir/Output/Count_Matrices/Gene_count_Matrices_filtered.tsv"
params.phenotype_TranscriptCount = "$projectDir/Output/Count_Matrices/Transcript_count_Matrices_filtered.tsv"
params.splicePCs = "$projectDir/Output/leafcutter_cluster/output_perind.counts.gz.PCs"

/* --Input: Calling genotype data from different chromosome -- */
   /* NOTE: The number of chromsomes can be altered based on user requirements  */

Channel
     .from (2..3)
     .map{chr -> tuple("${chr}",file("$projectDir/Output/eQTLGenoData/dataSet_genotypesChr${chr}.vcf.gz"))}
     .set {genotype_input_ch } 


/* --Input: Calling qqnormalized count data generated by leafcutter from different chromosome --*/

Channel
      .from (2..3)
      .map {chr  -> tuple("${chr}",file("$projectDir/Output/leafcutter_cluster/output_perind.counts.gz.qqnorm_chr${chr}"))}
      .set {phenotypeSplice_ch}


                               /* OUTPUT */
      
params.outputQTL = "$projectDir/Output"


               /*  --Path to supporting files: QTLtools R script for FDR correction of cis and trans-eQTL hits -- */
params.FDR_cis = "$projectDir/modules_dsl2/runFDR_cis_QTLtools.R"
params.FDR_trans = "$projectDir/modules_dsl2/qtltools_runFDR_ftrans_Mod.R"


                              def inputfiles() {

                                     log.info """\
                                       Cis QTLmapping  - N F   P I P E L I N E  F O R eQ T L DSL2
                                       ====================================================================
                                       Phenotype_SplicePCs          : ${params.splicePCs}
                                       Output-eQTL                  : ${params.outputQTL}
                                       """
                                       .stripIndent()
                              }

                              inputfiles()

/* Channel objects */
/* single channel objects */

phenotypeTranscript_ch = Channel.fromPath(params.phenotype_TranscriptCount)

phenotypeGene_ch = Channel.fromPath(params.phenotype_GeneCount)

splicepcs_ch = Channel.fromPath(params.splicePCs)

ch_FDR_cis = file(params.FDR_cis)

ch_FDR_trans = file(params.FDR_trans)

/* parameters declared in json file */

nominal_cis_ch = params.cis_nominal

permutations_cis_ch = params.cis_permutations

fdr_rate_cis_ch = params.cis_FDR

threshold_trans_ch = params.trans_threshold

permutations_trans_ch = params.trans_permutations

genotype_pcs_ch = params.genotype_pcs

phenotype_PCs_cis = params.phenotype_PCs_cis

phenotype_PCs_trans = params.phenotype_Pcs_trans

/* calling different process modules */

include { genotypeStratificationPCA } from './modules_dsl2/GenotypePCs'

include { transcriptCountsPCA } from './modules_dsl2/PhenotypePCs'

include { geneCountsPCA } from './modules_dsl2/PhenotypePCs'

include { rnaSplicePCS } from './modules_dsl2/PhenotypePCs'

include { transcriptCountsPCA_trans } from './modules_dsl2/PhenotypePCs_trans-eQTL'

include { geneCountsPCA_trans} from './modules_dsl2/PhenotypePCs_trans-eQTL'

include { rnaSplicePCS_trans } from './modules_dsl2/PhenotypePCs_trans-eQTL'

include { cisQTL_nominal } from './modules_dsl2/cis-eQTL'

include { cisQTL_permutation } from './modules_dsl2/cis-eQTL'

include { cisQTL_conditional} from './modules_dsl2/cis-eQTL'

include { trans_eQTL_nominal} from './modules_dsl2/trans-eQTL'

include { trans_eQTL_permu} from './modules_dsl2/trans-eQTL'

include { trans_eQTL_FDR} from './modules_dsl2/trans-eQTL'



workflow CISeQTL {

     take:

       genotypeStratificationPCA

       genotype_input_ch

       phenotypeTranscript_ch

       phenotypeGene_ch

       splicepcs_ch

       phenotypeSplice_ch

       ch_FDR_cis

       phenotype_PCs_cis
   
       nominal_cis_ch

       permutations_cis_ch

       fdr_rate_cis_ch

    main:
  
   /* phenotypes for cis-eQTL: Extracts the phenotypes from each chromosomes to perform chromosome wise cis-eQTL */

   transcriptCountsPCA(phenotypeTranscript_ch.collect(),genotype_input_ch.join(genotypeStratificationPCA.out),phenotype_PCs_cis)

   geneCountsPCA(phenotypeGene_ch.collect(), genotype_input_ch.join(genotypeStratificationPCA.out),phenotype_PCs_cis)

   rnaSplicePCS(splicepcs_ch.collect(),phenotypeSplice_ch.join(genotype_input_ch).join(genotypeStratificationPCA.out))

  /*cis-eQTL nominal and permuataion*/

   qtlmap_cis_geneCount = geneCountsPCA.out.phenotype_gene_Bed_ch.join(geneCountsPCA.out.cis_covariates_gene_ch).join(geneCountsPCA.out.genotypeQTL_gene_ch)

   qtlmap_cis_transcriptCount = transcriptCountsPCA.out.phenotype_transcript_Bed_ch.join(transcriptCountsPCA.out.cis_covariates_transcript_ch).join(transcriptCountsPCA.out.genotypeQTL_transcript_ch)
   
   qtlmap_cis_spliceCount = rnaSplicePCS.out.phenotype_splice_Bed_ch.join(rnaSplicePCS.out.cis_covariates_splice_ch).join(rnaSplicePCS.out.genotypeQTL_splice_ch)

   cisQTL_nominal(qtlmap_cis_geneCount.join(qtlmap_cis_transcriptCount).join(qtlmap_cis_spliceCount),nominal_cis_ch)
   
   cisQTL_permutation(qtlmap_cis_geneCount.join(qtlmap_cis_transcriptCount).join(qtlmap_cis_spliceCount),permutations_cis_ch)

   /*cis-eQTL conditional */

   qtlmap_cis_geneCount_cond = qtlmap_cis_geneCount.join(cisQTL_permutation.out.cis_permu_geneResults_ch)

   qtlmap_cis_transcriptCount_cond = qtlmap_cis_transcriptCount.join(cisQTL_permutation.out.cis_permu_transcritResults_ch)

   qtlmap_cis_spliceCount_cond = qtlmap_cis_spliceCount.join(cisQTL_permutation.out.cis_permu_splicingResults_ch)

   cisQTL_conditional(qtlmap_cis_geneCount_cond.join(qtlmap_cis_transcriptCount_cond).join(qtlmap_cis_spliceCount_cond),ch_FDR_cis,fdr_rate_cis_ch)

}

workflow TRANSeQTL {

   take:

       genotypeStratificationPCA

       genotype_input_ch

       phenotypeTranscript_ch

       phenotypeGene_ch

       splicepcs_ch

       phenotypeSplice_ch

       ch_FDR_trans

       phenotype_PCs_trans

       threshold_trans_ch

       permutations_trans_ch

   main:

   /* phenotypes for trans-eQTL: Extracts the phenotypes from all chromosomes to perform trans-eQTL for each variant */

   transcriptCountsPCA_trans(phenotypeTranscript_ch.collect(),genotype_input_ch.join(genotypeStratificationPCA.out),phenotype_PCs_trans)

   geneCountsPCA_trans(phenotypeGene_ch.collect(), genotype_input_ch.join(genotypeStratificationPCA.out),phenotype_PCs_trans)

   rnaSplicePCS_trans(splicepcs_ch.collect(),phenotypeSplice_ch.collect(), genotype_input_ch.join(genotypeStratificationPCA.out))

   /* trans-eQTL nominal, permuataion and FDR */

   qtlmap_trans_geneCount = geneCountsPCA_trans.out.phenotype_gene_Bed_ch.join(geneCountsPCA_trans.out.cis_covariates_gene_ch).join(geneCountsPCA_trans.out.genotypeQTL_gene_ch)

   qtlmap_trans_transcriptCount = transcriptCountsPCA_trans.out.phenotype_transcript_Bed_ch.join(transcriptCountsPCA_trans.out.cis_covariates_transcript_ch).join(transcriptCountsPCA_trans.out.genotypeQTL_transcript_ch)
   
   qtlmap_trans_spliceCount = rnaSplicePCS_trans.out.phenotype_splice_Bed_ch.join(rnaSplicePCS_trans.out.cis_covariates_splice_ch).join(rnaSplicePCS_trans.out.genotypeQTL_splice_ch)

   trans_eQTL_nominal(qtlmap_trans_geneCount.join(qtlmap_trans_transcriptCount).join(qtlmap_trans_spliceCount), threshold_trans_ch)

   trans_eQTL_permu(qtlmap_trans_geneCount.join(qtlmap_trans_transcriptCount).join(qtlmap_trans_spliceCount), permutations_trans_ch,threshold_trans_ch )
   
   trans_eQTL_FDR(trans_eQTL_nominal.out.gene_trans_nominal_hits_ch.join(trans_eQTL_permu.out.gene_trans_permu_hits_ch).join(trans_eQTL_nominal.out.transcript_trans_nominal_hits_ch).join(trans_eQTL_permu.out.transcript_trans_permu_hits_ch).join(trans_eQTL_nominal.out.splice_trans_nominal_hits_ch).join(trans_eQTL_permu.out.splice_trans_permu_hits_ch),ch_FDR_trans)

  }


workflow {

    main:

        /*genotypes covariates for both cis and trans*/
        genotypeStratificationPCA(genotype_input_ch, genotype_pcs_ch)

        CISeQTL(genotypeStratificationPCA,genotype_input_ch,phenotypeTranscript_ch,phenotypeGene_ch,splicepcs_ch,phenotypeSplice_ch,ch_FDR_cis,phenotype_PCs_cis,nominal_cis_ch,permutations_cis_ch,fdr_rate_cis_ch)

        TRANSeQTL(genotypeStratificationPCA,genotype_input_ch,phenotypeTranscript_ch,phenotypeGene_ch,splicepcs_ch,phenotypeSplice_ch,ch_FDR_trans,phenotype_PCs_trans,threshold_trans_ch,permutations_trans_ch)
}