module load GNU/7.3.0-2.30  OpenMPI/3.1.1-CUDA
module load R/3.6.0-X11-20180604

# Analysis in R
setwd("/mnt/home/stopnise/amoA_MiSeq_sequencing/AOBpart")
library(dada2)
library(phyloseq)

path="~/amoA_MiSeq_sequencing/AOBpart/cutadapt_before_DADA2"
outpath="/mnt/research/ShadeLab/WorkingSpace/Stopnisek/Soil_aggregates"

#list.files(path)

# Forward and reverse fastq filenames have format: SAMPLENAME_R1_001.fastq and SAMPLENAME_R2_001.fastq
fnFs <- sort(list.files(path, pattern="_trim_R1.fq", full.names = TRUE)) #pattern can be modify
fnRs <- sort(list.files(path, pattern="_trim_R2.fq", full.names = TRUE)) #pattern can be modify
if(length(fnFs) != length(fnRs)) stop("Forward and reverse files do not mach")

# Extract sample names, assuming filenames have format: SAMPLENAME_XXX.fastq
sample.names <- sapply(strsplit(basename(fnFs), "_R"), `[`, 1)

# Place filtered files in filtered/ subdirectory
#filtFs <- file.path(path, "filtered", paste0(sample.names, "_filt_F.fastq.gz"))
#filtRs <- file.path(path, "filtered", paste0(sample.names, "_filt_R.fastq.gz"))

filtFs <- file.path(outpath, "filtered_240", paste0(sample.names, "_filt_F.fastq.gz"))
filtRs <- file.path(outpath, "filtered_240", paste0(sample.names, "_filt_R.fastq.gz"))

#Set truncLen and minLen according to your dataset
#AOB amoA assembly: truncLen=c(229,229), minLen = 229 
out <- dada2::filterAndTrim(fnFs, filtFs, fnRs, filtRs, truncLen=c(240,240), 
                            minLen = 240, truncQ=2, maxN=0, maxEE=c(2,2), compress=TRUE, 
                            rm.phix=TRUE,  multithread=TRUE)
head(out)

errF <- dada2::learnErrors(filtFs, multithread=TRUE)
errR <- dada2::learnErrors(filtRs, multithread=TRUE)

dadaFs <- dada2::dada(filtFs, err=errF, multithread=TRUE)
dadaRs <- dada2::dada(filtRs, err=errR, multithread=TRUE)

mergers <- dada2::mergePairs(dadaFs, filtFs, dadaRs, filtRs, verbose=TRUE)

seqtab <- dada2::makeSequenceTable(mergers, orderBy = "abundance")
dim(seqtab)

table(nchar(dada2::getSequences(seqtab)))

seqtab2 <- seqtab[,nchar(colnames(seqtab)) %in% 449:453] 

#remove chimera
seqtab.nochim <- dada2::removeBimeraDenovo(seqtab2, method="consensus", multithread=TRUE, verbose=TRUE)
dim(seqtab.nochim)

#save ASV as fasta
dada2::uniquesToFasta(dada2::getUniques(seqtab.nochim), fout="ASV.fa", 
                      ids=paste0("ASV", seq(length(dada2::getUniques(seqtab.nochim)))))

#rename the ASV from read sequence to ASV#
asvTable=seqtab.nochim
colnames(asvTable)=paste0("ASV", seq(length(dada2::getUniques(asvTable))))
write.table(t(asvTable), "Documents/git/SoilAggregates/AOB/ASVna_table_AOB.txt", sep='\t') #ASV table output for AOB

#How many chimeric reads are there?
sum(asvTable)/sum(seqtab2)

# creating summary table
getN <- function(x) sum(dada2::getUniques(x))
track <- cbind(out, sapply(dadaFs, getN), sapply(dadaRs, getN), sapply(mergers, getN), rowSums(asvTable))
# If processing a single sample, remove the sapply calls: e.g. replace sapply(dadaFs, getN) with getN(dadaFs)
colnames(track) <- c("input", "filtered", "denoisedF", "denoisedR", "merged", "nonchim")
head(track)

write.delim(x = track, 'Documents/git/SoilAggregates/AOB_dada2_readStat.txt')

library(gt)
library(dplyr)

track = as.data.frame(track)
track <- data.frame(sampleID = row.names(track), track)
track = tibble::remove_rownames(track)
track$sampleID = sapply(strsplit(track$sampleID, "_AOB"), `[`, 1)

track %>%
  gt(rowname_col = "sampleID") %>%
  tab_stubhead(label = "Sample ID") %>%
  tab_header(
    title = md("**Read processing Statistics**"),
    subtitle = "Using DADA2 package in R and amoA AOB amplicons") %>%
  tab_row_group(
    group = "Montcalm",
    rows = 1:21) %>%
  tab_row_group(
    group = "Saginaw Valley",
    rows = 22:42) %>%
  cols_label(
    input = "Input",
    filtered = "Quality\nfiltered",
    denoisedF = "Denoised forward",
    denoisedR = "Denoised reverse",
    merged = "Merged",
    nonchim = "Without chimera")

#create ASV table for phyloseq

samples.out <- rownames(asvTable)
subject <- sapply(strsplit(samples.out, "_AOB"), `[`, 1)
site <- substr(samples.out,1,1)

samdf <- data.frame(Sample=samples.out, Site=site)
write.table(samdf, 'map_AOB.txt', sep='\t') #add outside R soil size and replicate

mapAOB=read.table('~/Documents/git/SoilAggregates/AOB/map_AOB.txt', sep='\t', header=T, row.names=1)

ps <- phyloseq::phyloseq(otu_table(asvTable, taxa_are_rows=FALSE), 
                         sample_data(mapAOB))

#rename ASV from sequences to ASV#
library(Biostrings)
dna <- Biostrings::DNAStringSet(taxa_names(ps))
names(dna) <- taxa_names(ps)
ps <- merge_phyloseq(ps, dna)
taxa_names(ps) <- paste0("ASV", seq(ntaxa(ps)))
ps

#' Joining nucleic acid ASV based on their amino acid sequences (translated using seqkit tool)
#' command for seqkit
#' seqkit translate -T 11 -f 2 ASV.fa --clean > ASV_AA.fa
#' where -T 11 represent frame usage for bacteria
#' -f 2 start from2nd base in the sequence
#' --clean removes the stop codon symbol * into X
#' Also convert .fa to .tab using seqkit fx2tab comand

AOB_table=phyloseq_to_df(ps, addtax=F)
head(AOB_table)

AAaob=read.table("Documents/git/SoilAggregates/AOB/ASV_AA_AOB.tab", header=F)
names(AAaob)[1]='OTU'

AA_aob_taxa=AAaob %>% 
  left_join(AOB_table) %>%
  pivot_longer(!c(V2, OTU), names_to = "sampleID", values_to = "count") %>%
  filter(!(OTU %in% c("ASV924","ASV959",'ASV1021','ASV1059'))) %>%
  group_by(V2, sampleID) %>%
  summarize(count=sum(count)) %>%
  dplyr::filter(!grepl("X", V2)) %>%
  pivot_wider(names_from = sampleID,
              values_from = count) 

AA_aob_taxa$AAasv=paste0("AA.ASV", seq(length(AA_aob_taxa$V2)))
colnames(AA_aob_taxa)=str_remove_all(colnames(AA_aob_taxa),"_trim_filt_F.fastq.gz") 

#Writing out amino acid sequences:
write.table(data.frame(x=AA_aob_taxa$AAasv, y=AA_aob_taxa$V2),"~/Documents/git/SoilAggregates/AOB/AOBamino.txt", sep='\t')
#' Writing out the amino acid ASV table
write_delim(AA_aob_taxa, '~/Documents/git/SoilAggregates/AOB/AOB_AA_table.txt') 

#' **************************************************
#' Statistical analysis
#' **************************************************

#' Creating an ASV table (ASV based on the AA sequeces)
AA_aob_taxa=read.delim('Documents/git/SoilAggregates/AOB/AOB_AA_table.txt',sep = ' ')
mapAOB_raw=read.table('Documents/git/SoilAggregates/AOB/map_AOB.txt', sep='\t', header=T, row.names=1)

AOBtable=AA_aob_taxa[-1] #remove the sequences

#' need to rename the colnames and remove anything following "_AOB"
samples.out <- colnames(AOBtable)
subject <- sapply(strsplit(samples.out, "_AOB"), `[`, 1)
colnames(AOBtable)=subject
rownames(AOBtable)=AOBtable$AAasv
AOBtable$AAasv=NULL
AOBtable=as.matrix(AOBtable)

#' same for the map file
rownames(mapAOB) <- sapply(strsplit(rownames(mapAOB), "_AOB"), `[`, 1)

library(vegan)
set.seed(533)
asvAOB=AOBtable
rownames(asvAOB)=asvAOB$AAasv
asvAOB$AAasv=NULL
asvAOB.rare <- t(rrarefy(t(asvAOB), 40000)) 
AOBabun <- decostand(asvAOB.rare, method = 'total', MARGIN = 2)
rownames(mapAOB) <- sapply(strsplit(rownames(mapAOB), "_trim"), `[`, 1)
rownames(mapAOB) == colnames(AOBabun)
length(rownames(ASVaob.rare))
#' Alpha diversity measurements
AOBs <- specnumber(asvAOB.rare,MARGIN=2)
AOBh <- vegan::diversity(t(asvAOB.rare), "shannon")
AOBpielou=AOBh/log(AOBs)

mapAOB$Richness <- AOBs
mapAOB$Shannon <- AOBh
mapAOB$Pielou <- AOBpielou 

RichnessAOB <- ggplot(mapAOB, aes(x=as.factor(Size),y=Richness, fill=Site)) +
  geom_boxplot() +
  scale_fill_manual(values = c("#009e73", "#0072b2")) + 
  scale_color_manual(values = c("#009e73", "#0072b2")) + 
  labs(x='Size (mm)', y='Richness', title='AOB') +
  theme_classic()

ShannonAOB <- ggplot(mapAOB, aes(x=as.factor(Size),y=Shannon, fill=Site)) +
  geom_boxplot()+
  scale_fill_manual(values = c("#009e73", "#0072b2")) + 
  scale_color_manual(values = c("#009e73", "#0072b2")) + 
  labs(x='Size (mm)', y='Shannon', title='AOB') +
  theme_classic()

#' Alpha diversity statistics
mapAOB %>%
  group_by(Site, Size) %>%
  summarise(minRich=min(Richness),
            maxRich=max(Richness),
            minShan=min(Shannon),
            maxShan=max(Shannon))
#' ANOVA
alpha.site.aob.aov <- aov(Richness ~ Site, #replace Richness with Shannon
                          data = mapAOB) 
alpha.size.aob.aov <- aov(mapAOB$Shannon ~ Size , #replace Richness with Shannon
                          data = mapAOB) 
alpha.size.M.aob.aov <- aov(Shannon ~ Size ,  #replace Richness with Shannon
                            data = mapAOB[mapAOB$Site == 'M',])
alpha.size.S.aob.aov <- aov(Shannon ~ Size , #replace Richness with Shannon
                            data = mapAOB[mapAOB$Site == 'S',])

# Summary of the analysis
summary(alpha.site.aob.aov)
summary(alpha.size.aob.aov)
summary(alpha.size.M.aob.aov)
summary(alpha.size.S.aob.aov) 

#' Are richness and Shannon index different at same soil size when comparing 
#' two soils?
stat.test.rich.aob <- mapAOB %>%
  group_by(Size) %>%
  t_test(Richness ~ Site) %>%
  adjust_pvalue(method = "BH") %>%
  add_significance()
stat.test.rich.aob # Two soils are not sign. different 

stat.test.shan.aob <- mapAOB %>%
  group_by(Size) %>%
  t_test(Shannon ~ Site) %>%
  adjust_pvalue(method = "BH") %>%
  add_significance()
stat.test.shan.aob # Only at the 2 mm particles differ significantly 

#' Is alpha diversity different with soil particle size?
stat.test.rich.size.aob <- mapAOB %>%
  group_by(Site) %>%
  t_test(Richness ~ Size) %>%
  adjust_pvalue(method = "BH") %>%
  add_significance()
stat.test.rich.size.aob # No statistical significant differences

#' Beta diversity
#' Combined dataset
asvAOB.b.BC <- vegdist(t(asvAOB.rare), method="bray")
asvAOB.b.J <- vegdist(t(asvAOB.rare), method="jaccard")
asvAOB.b.bc.pcoa <- cmdscale(asvAOB.b.BC, eig=T)
asvAOB.b.j.pcoa <- cmdscale(asvAOB.b.J, eig=T)

mapAOB$Axis1.BC <- asvAOB.b.bc.pcoa$points[,1]
mapAOB$Axis2.BC <- asvAOB.b.bc.pcoa$points[,2]
mapAOB$Axis1.J <- asvAOB.b.j.pcoa$points[,1]
mapAOB$Axis2.J <- asvAOB.b.j.pcoa$points[,2]
ax1.bc.asvAOB.b <- asvAOB.b.bc.pcoa$eig[1]/sum(asvAOB.b.bc.pcoa$eig)
ax2.bc.asvAOB.b <- asvAOB.b.bc.pcoa$eig[2]/sum(asvAOB.b.bc.pcoa$eig)
ax1.j.asvAOB.b <- asvAOB.b.j.pcoa$eig[1]/sum(asvAOB.b.j.pcoa$eig)
ax2.j.asvAOB.b <- asvAOB.b.j.pcoa$eig[2]/sum(asvAOB.b.j.pcoa$eig)

pcoa.BC.asvAOB.b <- ggplot(mapAOB, aes(x=Axis1.BC, y=Axis2.BC)) +
  theme_classic() +
  geom_point(aes(col=Site, size=Size))+
  scale_color_manual(values = c("#009e73", "#0072b2")) + 
  theme(#legend.position = c(.5,.5),
        legend.position = 'none',
        legend.background = element_rect(fill="transparent"),
        legend.text = element_text(size=8),
        legend.title = element_text(size=10))+
  labs(x=paste('PCoA1 (',100*round(ax1.bc.asvAOB.b,3),'%)',sep=''),
       y=paste('PCoA2 (',100*round(ax2.bc.asvAOB.b,3),'%)', sep=''), 
       alpha='Size (mm)', title='Bray-Curtis - AOB')

pcoa.J.asvAOB.j=ggplot(mapAOB, aes(x=Axis1.J, y=Axis2.J)) +
  theme_classic() +
  geom_point(aes(col=Site, size=Size))+
  scale_color_manual(values = c("#009e73", "#0072b2")) + 
  #scale_alpha_continuous(range = c(0.1, 1)) + 
  theme(#legend.position = c(.5,.5),
        legend.position='none',
        legend.background = element_rect(fill="transparent"),
        legend.text = element_text(size=8),
        legend.title = element_text(size=10))+
  labs(x=paste('PCoA1 (',100*round(ax1.j.asvAOB.b,3),'%)',sep=''),
       y=paste('PCoA2 (',100*round(ax2.j.asvAOB.b,3),'%)', sep=''), 
       alpha='Size (mm)', title='Jaccard - AOB')

#' Beta diversity on separated dataset
#' MRC
asvAOB.M=asvAOB.rare[,as.character(mapAOB$Site)=='M']
mapAOB.M=mapAOB[mapAOB$Site=='M',]
asvAOB.M=asvAOB.M[rowSums(asvAOB.M)>0,] # remove ASV not present in the dataset 

asvAOB.M.BC <- vegdist(t(asvAOB.M), method="bray")
asvAOB.M.J <- vegdist(t(asvAOB.M), method="jaccard")
asvAOB.M.bc.pcoa <- cmdscale(asvAOB.M.BC, eig=T)
asvAOB.M.j.pcoa <- cmdscale(asvAOB.M.J, eig=T)

mapAOB.M$Axis1.BC.M <- asvAOB.M.bc.pcoa$points[,1]
mapAOB.M$Axis2.BC.M <- asvAOB.M.bc.pcoa$points[,2]
mapAOB.M$Axis1.J.M <- asvAOB.M.j.pcoa$points[,1]
mapAOB.M$Axis2.J.M <- asvAOB.M.j.pcoa$points[,2]
ax1.bc.asvAOB.M <- asvAOB.M.bc.pcoa$eig[1]/sum(asvAOB.M.bc.pcoa$eig)
ax2.bc.asvAOB.M <- asvAOB.M.bc.pcoa$eig[2]/sum(asvAOB.M.bc.pcoa$eig)
ax1.j.asvAOB.M <- asvAOB.M.j.pcoa$eig[1]/sum(asvAOB.M.j.pcoa$eig)
ax2.j.asvAOB.M <- asvAOB.M.j.pcoa$eig[2]/sum(asvAOB.M.j.pcoa$eig)

pcoa.BC.asvAOB.M <- ggplot(mapAOB.M, aes(x=Axis1.BC.M, y=Axis2.BC.M, size=Size, col=Site)) +
  theme_classic() +
  geom_point()+
  scale_color_manual(values = c("#009e73")) + 
  theme(legend.position ='none')+
  labs(x=paste('PCoA1 (',100*round(ax1.bc.asvAOB.M,3),'%)',sep=''),
       y=paste('PCoA2 (',100*round(ax2.bc.asvAOB.M,3),'%)', sep=''), 
       alpha='Size (mm)')

pcoa.J.asvAOB.M <- ggplot(mapAOB.M, aes(x=Axis1.J.M, y=Axis2.J.M, size=Size, col=Site)) +
  theme_classic() +
  geom_point()+
  scale_color_manual(values = c("#009e73")) + 
  theme(legend.position ='none')+
  labs(x=paste('PCoA1 (',100*round(ax1.j.asvAOB.M,3),'%)',sep=''),
       y=paste('PCoA2 (',100*round(ax2.j.asvAOB.M,3),'%)', sep=''), 
       alpha='Size (mm)', title='Jaccard - AOB')

#' SVERC
asvAOB.S=asvAOB.rare[,as.character(mapAOB$Site)=='S']
mapAOB.S=mapAOB[mapAOB$Site=='S',]
asvAOB.S=asvAOB.S[rowSums(asvAOB.S)>0,] # remove ASV not present in the dataset 

asvAOB.S.BC <- vegdist(t(asvAOB.S), method="bray")
asvAOB.S.J <- vegdist(t(asvAOB.S), method="jaccard")
asvAOB.S.bc.pcoa <- cmdscale(asvAOB.S.BC, eig=T)
asvAOB.S.j.pcoa <- cmdscale(asvAOB.S.J, eig=T)

mapAOB.S$Axis1.BC.S <- asvAOB.S.bc.pcoa$points[,1]
mapAOB.S$Axis2.BC.S <- asvAOB.S.bc.pcoa$points[,2]
mapAOB.S$Axis1.J.S <- asvAOB.S.j.pcoa$points[,1]
mapAOB.S$Axis2.J.S <- asvAOB.S.j.pcoa$points[,2]
ax1.bc.asvAOB.S <- asvAOB.S.bc.pcoa$eig[1]/sum(asvAOB.S.bc.pcoa$eig)
ax2.bc.asvAOB.S <- asvAOB.S.bc.pcoa$eig[2]/sum(asvAOB.S.bc.pcoa$eig)
ax1.j.asvAOB.S <- asvAOB.S.j.pcoa$eig[1]/sum(asvAOB.S.j.pcoa$eig)
ax2.j.asvAOB.S <- asvAOB.S.j.pcoa$eig[2]/sum(asvAOB.S.j.pcoa$eig)

pcoa.BC.asvAOB.S <- ggplot(mapAOB.S, aes(x=Axis1.BC.S, y=Axis2.BC.S, size=Size, col=Site)) +
  theme_classic() +
  geom_point()+
  scale_color_manual(values = c("#0072b2")) + 
  theme(legend.position ='none')+
  labs(x=paste('PCoA1 (',100*round(ax1.bc.asvAOB.S,3),'%)',sep=''),
       y=paste('PCoA2 (',100*round(ax2.bc.asvAOB.S,3),'%)', sep=''), 
       alpha='Size (mm)', title = 'Bray-Curtis - AOB')

pcoa.J.asvAOB.S <- ggplot(mapAOB.S, aes(x=Axis1.J.S, y=Axis2.J.S, size=Size, col=Site)) +
  theme_classic() +
  geom_point()+
  scale_color_manual(values = c("#0072b2")) + 
  theme(legend.position ='none')+
  labs(x=paste('PCoA1 (',100*round(ax1.j.asvAOB.S,3),'%)',sep=''),y=paste('PCoA2 (',100*round(ax2.j.asvAOB.S,3),'%)', sep=''), 
       alpha='Size (mm)', title='Jaccard - AOB')

# Create a plot combining all PCoA graphs (AOA and AOB, Bray-Curtis)
ggarrange(pcoa.BC.asvAOA.M,pcoa.BC.asvAOA.S, 
          pcoa.BC.asvAOB.M,pcoa.BC.asvAOB.S, 
          labels = c("A", "B", "C", "D"), nrow = 2, ncol = 2)

#' Testing the effect of size, site and chemical parameters on the community 
#' using PERMANOVA
#' Factors: Site, Size, OM, NO3, NH4, N
set.seed(003)

#' Full dataset (M and S) 
adonis(asvAOB.b.BC~mapAOB$Site) # R2=0.919, p=0.001

#' M and S separated 
adonis(asvAOB.S.BC~mapAOB.S$Size) # R2=0.311, p=0.001
adonis(asvAOB.M.BC~mapAOB.M$Size) # R2=0.452, p=0.001

#' Chemical parameters for full SVERC
adonis(asvAOB.S.BC~mapAOB.S$OM)  # R2=0.196, p=0.003
adonis(asvAOB.S.BC~mapAOB.S$N)   # R2=0.078, p=0.141
adonis(asvAOB.S.BC~mapAOB.S$NO3) # R2=0.120, p=0.046
adonis(asvAOB.S.BC~mapAOB.S$NH4) # R2=0.071, p=0.222

#' Chemical analysis for MRC where 2mm soil particles are removed because no 
#' chemistry was done for them
asvAOB.M.BC.2mm <- vegdist(t(asvAOB.M[,-c(16,17,18)]), method="bray") # removing 2 mm samples
mapAOB.M.2=mapAOB.M %>% filter(Size<2)
adonis(asvAOB.M.BC.2mm~mapAOB.M.2$OM) # R2=0.087, p=0.146
adonis(asvAOB.M.BC.2mm~mapAOB.M.2$N)  # R2=0.135, p=0.039
adonis(asvAOB.M.BC.2mm~mapAOB.M.2$NO3)# R2=0.081, p=0.213
adonis(asvAOB.M.BC.2mm~mapAOB.M.2$NH4)# R2=0.087, p=0.172

#############################
#' Calculating beta dispersal

#'MRC 
## Calculate multivariate dispersions
mod.M.aob <- betadisper(vegdist(t(asvAOB.M), method="bray"), mapM$Size)
mod.M.aob

## Perform test
anova(mod.M.aob)

## Permutation test for F
permutest(mod.M.aob, pairwise = TRUE, permutations = 99)

#' Tukey's Honest Significant Differences
(mod.M.aob.HSD <- TukeyHSD(mod.M.aob))
plot(mod.M.aob.HSD)

#' Plot the groups and distances to centroids on the
## first two PCoA axes with data ellipses instead of hulls
plot(mod.M.aob, ellipse = TRUE, hull = FALSE, seg.lty = "dashed") # 1 sd data ellipse

#' Draw a boxplot of the distances to centroid for each group
boxplot(mod.M.aob)

#' SVERC 
## Calculate multivariate dispersions
mod.S.aob <- betadisper(asvAOB.S.BC, mapAOB.S$Size)
mod.S.aob

#' Perform test
anova(mod.S.aob)

#' Permutation test for F
permutest(mod.S.aob, pairwise = TRUE, permutations = 99)

#' Tukey's Honest Significant Differences
(mod.S.aob.HSD <- TukeyHSD(mod.S.aob))
plot(mod.S.aob.HSD)

#' Plot the groups and distances to centroids on the
#' first two PCoA axes with data ellipses instead of hulls
plot(mod.S.aob, ellipse = TRUE, hull = FALSE, seg.lty = "dashed") # 1 sd data ellipse

#' Draw a boxplot of the distances to centroid for each group
boxplot(mod.S.aob)


#################################################
#' Calculating the phylogenetic diversity (Faith's diversity index (PD))
library(btools)

tax_df=tax_filtered[tax_filtered$OTU %in% rownames(OTU.rare),]
rownames(tax_df)=tax_df$OTU
tax_df$OTU=NULL

TREEaob = read_tree("AOB/AOB_amino.tre")
AOBp=phyloseq(otu_table(as.matrix(asvAOB.rare), taxa_are_rows = T), sample_data(mapAOB), TREEaob)

PD.aob <- estimate_pd(AOBp) %>%
  rownames_to_column('sample_ID')

mapPD.aob=mapAOB
mapPD.aob$sample_ID=rownames(mapPD.aob)

PD.aob %>%
  left_join(mapPD.aob) %>%
  ggplot(aes(x=factor(Size), y=PD, color=Site)) +
  geom_boxplot() +
  theme_classic()+
  scale_color_manual(values = c("#009e73", "#0072b2")) +
  labs(x=NULL) 

PD.aob.df=PD.aob %>%
  left_join(mapPD.aob)

#' ANOVA
PD.aob.site.aov <- aov(PD ~ Site, data = PD.aob.df) 
PD.aob.size.aov <- aov(PD ~ Size , data = PD.aob.df)
PD.aob.size.M.aov <- aov(PD ~ Size , data = PD.aob.df[PD.aob.df$Site == 'M',])
PD.aob.size.S.aov <- aov(PD ~ Size, data = PD.aob.df[PD.aob.df$Site == 'S',])

# Summary of the analysis
summary(PD.aob.site.aov)
summary(PD.aob.size.aov)
summary(PD.aob.size.M.aov)
summary(PD.aob.size.S.aov)
#' Significant difference between istes but nothing else

#' Does phylogenetic signal/depth differ between soils and different soil 
#' particle sizes?
stat.test.pd.aob <- PD.aob.df %>%
  group_by(Size) %>%
  t_test(PD ~ Site) %>%
  adjust_pvalue(method = "BH") %>%
  add_significance()
stat.test.pd.aob  
# Difference between the MRC and SVERC only at 0.25 mm

#######################################
#' Distribution of ASVs by site and size

pheatmap(asvAOB.rare, 
         color=colorRampPalette(brewer.pal(n = 11,name="Oranges"))(100),
         cutree_cols = 2)

#' filter low abundant and low prevalent ASVs (3 or more samples)
asvAOB.rare.filt=asvAOB.rare[rowSums(asvAOB.rare)>2000,]

pheatmap(asvAOB.rare.filt, 
         color=colorRampPalette(brewer.pal(n = 11,name="Oranges"))(8),
         cutree_cols = 2)

###########################################
#' Investigating if any AOB correlated with soil particles size
aob_mtx=data.frame(t(AOBabun))
aob.cor.pearson = cor(aob_mtx, mapAOB$Size, method = "pearson")
data.frame(asv=rownames(aob.cor.pearson), pearson=aob.cor.pearson[,1]) %>%
  select(asv, pearson) %>%
  filter(pearson > 0.5)
#AA.ASV116 has pearson correlation of 0.59

cor.aobASV116 = glm(aob_mtx$AA.ASV116 ~ mapAOB$Size)
summary(cor.aobASV116)

plot(aob_mtx$AA.ASV116 ~ mapAOB$Size,
     xlab="Size (mm)", ylab="Relative abundance", main="AA.ASV116")
