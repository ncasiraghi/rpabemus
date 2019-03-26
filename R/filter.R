#' filter
#'
#' @param coverage_binning Bins of coverage into which divide allelic fractions. default: 50
filter = function(i,
                  chromosomes,
                  patient_folder,
                  plasma.folder,
                  germline.folder,
                  out1,
                  out2,
                  out3,
                  coverage_binning=50){
  chrom = chromosomes[i]
  # create chromsome sub-folder
  chromdir = file.path(patient_folder,chrom)
  dir.create(chromdir,showWarnings = T)
  setwd(chromdir)
  # import files
  plasma_snvs = list.files(file.path(plasma.folder,"snvs"),pattern = paste0("_",chrom,".snvs"),full.names = T)
  n.rows.plasma_snvs = as.numeric(unlist(strsplit(trimws(x = system(paste("wc -l",plasma_snvs),intern = T),which = "left"),split = " "))[[1]])
  if(n.rows.plasma_snvs == 1){
    return()
  }
  snvs = fread(plasma_snvs,stringsAsFactors = F,showProgress = F,header = F,skip = 1,na.strings = "",colClasses = list(character=3,4,15),verbose = F)
  snvs = unique(snvs)
  snvs = data.frame(snvs)
  names(snvs)=c("chr","pos","ref","alt","A","C","G","T","af","cov","Ars","Crs","Grs","Trs","dbsnp")
  if(nrow(snvs)==0){
    return()
  }
  # F1) Custom basic filters [ in plasma/tumor ]
  out <-  mclapply(seq(1,nrow(snvs),1),
                   CheckAltReads,
                   snvs=snvs,
                   mc.cores = mc.cores)
  snvs <- fromListToDF(out)
  snvs <- snvs[which(snvs$af > 0 ),,drop=F]
  snvs <- snvs[which(snvs$cov >= mincov ),,drop=F]
  snvs <- snvs[which(snvs$cov.alt >= minalt ),,drop=F]
  snvs <- unique(snvs)
  if(nrow(snvs)==0){
    return()
  }
  # print filtered positions and grep these pos only from pileup file of germline sample
  cat(unique(snvs$pos),sep = "\n",file = file.path(chromdir,"postogrep.txt"),append = F)
  controlfolder_pileup <- list.files(file.path(germline.folder,"pileup"),pattern = paste0("_",chrom,".pileup"),full.names = T)
  cmd = paste("awk -F'\t' '{if (FILENAME == \"postogrep.txt\") { t[$1] = 1; } else { if (t[$2]) { print }}}' postogrep.txt",controlfolder_pileup,"> filtered.germline.pileup.txt")
  system(cmd)
  ctrl.pileup = fread("filtered.germline.pileup.txt",stringsAsFactors = F,showProgress = T,header = F,na.strings = "",colClasses = list(character=10))
  #system("rm postogrep.txt filtered.germline.pileup.txt")
  ctrl.pileup = ctrl.pileup[,1:9]
  ctrl.pileup = unique(ctrl.pileup)
  ctrl.pileup = data.frame(ctrl.pileup)
  names(ctrl.pileup)=c("chr","pos","ref","A","C","G","T","af","cov")
  # F1) Custom basic filters [ in germline ]
  common = merge(x = snvs,y = ctrl.pileup,by = c("chr","pos","ref"),all.x = T,suffixes = c("_case","_control"))
  toremove = which(common$cov_control < mincovgerm | common$af_control > maxafgerm )
  if(length(toremove)>0){
    putsnvs <- common[-toremove,,drop=F]
  } else {
    putsnvs <- common
  }
  if(nrow(putsnvs) > 0){
    # F2) Filters on Variant Allelic Fraction and add pbem [ in plasma/tumor ]
    # import pbem of this chrom
    tabpbem_file = list.files(pbem_dir, pattern = paste0('bperr_',chrom,'.tsv'),full.names = T)
    tabpbem = fread(input = tabpbem_file,stringsAsFactors = F,showProgress = F,header = F,colClasses = list(character=2,character=5),data.table = F)
    colnames(tabpbem) <- c("group","chr","pos","ref","dbsnp","gc","map","uniq","is_rndm","tot_coverage","total.A","total.C","total.G","total.T","n_pos_available",'n_pos_af_lth','n_pos_af_gth','count.A_af_gth','count.C_af_gth','count.G_af_gth','count.T_af_gth',"bperr","tot_reads_supporting_alt")
    # TABLE 1
    chrpmF1 = apply_AF_filters(chrpmF1=putsnvs,
                               AFbycov=AFbycov,
                               mybreaks=define_cov_bins(coverage_binning)[[1]],
                               af.threshold.table=minaf_cov_corrected,
                               minaf=minaf,
                               mc.cores=mc.cores)
    chrpmF1 = chrpmF1[,c("chr","pos","ref","alt","A_case","C_case","G_case","T_case",
                         "af_case","cov_case","Ars","Crs","Grs","Trs","rev.ref","fwd.ref","cov.alt","rev.alt","fwd.alt",
                         "strandbias","A_control","C_control","G_control","T_control","af_control","cov_control","af_threshold")]
    chrpmF1$group <- paste(chrpmF1$chr,chrpmF1$pos,chrpmF1$ref,sep = ":")
    cpmf1 = merge(x = chrpmF1,y = tabpbem,by = c("group","chr","pos","ref"),all.x = T)
    cpmf1 = cpmf1[,c("group","chr","pos","ref","dbsnp","alt","A_case","C_case","G_case","T_case",
                     "af_case","cov_case","Ars","Crs","Grs","Trs","rev.ref","fwd.ref","cov.alt","rev.alt","fwd.alt",
                     "strandbias","A_control","C_control","G_control","T_control","af_control","cov_control","af_threshold",
                     "gc","map","uniq","is_rndm","tot_coverage","total.A","total.C","total.G","total.T",
                     "n_pos_available","n_pos_af_lth","n_pos_af_gth","count.A_af_gth","count.C_af_gth","count.G_af_gth","count.T_af_gth",
                     "bperr","tot_reads_supporting_alt")]

    # Add sample/patient IDs
    cpmf1 = add_names(pm = cpmf1,
                      name.patient = name.patient,
                      name.plasma = name.plasma,
                      name.germline = name.germline)

    # compute pbem allele
    Nids = which(cpmf1$alt=='N')
    if(length(Nids)>0){cpmf1 = cpmf1[-Nids,]}
    cpmf1 = cpmf1[which(!is.na(cpmf1$cov_control)),,drop=F]
    if(nrow(cpmf1)==0){
      return()
    }
    out = mclapply(seq(1,nrow(cpmf1),1),
                   compute_pbem_allele,
                   abemus=cpmf1,
                   mc.cores = mc.cores)
    cpmf1 = fromListToDF(out)

    # add CLASS standard
    cpmf1 = add_class(pmtab = cpmf1)

    # TABLE 2
    cpmf1$af_threshold[which(is.na(cpmf1$af_threshold))] <- -1
    cpmf2 = cpmf1[which(cpmf1$af_case >= cpmf1$af_threshold),,drop=F]
    if(nrow(cpmf2)==0){
      return()
    }
    cpmf2$af_threshold[which(cpmf2$af_threshold == -1)] <- NA

    # TABLE 3
    cpmf3 = add_class_xbg(pmtab = cpmf2,xbg = as.numeric(tab_bg_pbem$background_pbem))
    cpmf3$bperr[which(cpmf3$bperr > 0.2)] = 0.2
    cpmf3$bperr[which(is.na(cpmf3$bperr))] = 0.2 # assign high pbem if it is NA
    if(nrow(cpmf3)>0){
      pbem_coverage_filter = sapply(1:nrow(cpmf3), function(k) tab_cov_pbem[min(which(covs>=cpmf3$cov_case[k])),min(which(afs>=cpmf3$bperr[k]))])
      cpmf3$filter.pbem_coverage <- pbem_coverage_filter
      cpmf3$pass.filter.pbem_coverage = 0
      cpmf3$pass.filter.pbem_coverage[which(cpmf3$af_case >= cpmf3$filter.pbem_coverage)] = 1
    }

    # Return chromosome tables
    write.table(cpmf1,file = 'chrpm_f1.tsv',sep = '\t',col.names = F,row.names = F,quote = F)
    write.table(cpmf2,file = 'chrpm_f2.tsv',sep = '\t',col.names = F,row.names = F,quote = F)
    write.table(cpmf3,file = 'chrpm_f3.tsv',sep = '\t',col.names = F,row.names = F,quote = F)
    cat(paste(colnames(cpmf1),collapse='\t'),file = file.path(patient_folder,out1),sep = '\n')
    cat(paste(colnames(cpmf2),collapse='\t'),file = file.path(patient_folder,out2),sep = '\n')
    cat(paste(colnames(cpmf3),collapse='\t'),file = file.path(patient_folder,out3),sep = '\n')
  } else {
    return()
  }
}