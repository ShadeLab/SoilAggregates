setwd('Documents/git/SoilAggregates/')
library(rmarkdown)
tinytex::install_tinytex()
tinytex::reinstall_tinytex()
library(tinytex)
render("submission/manuscript.Rmd", output_format="all")
