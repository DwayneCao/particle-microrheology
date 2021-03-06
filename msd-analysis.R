# msd-analysis.R
#
# Matthias C. Munder  
# matthiasmunder@gmail.com  
# http://matthiasmunder.de
#    
# ### Description: R-code for MSD analysis of particle trajectories. Written by
# a biologist ;-)
# 
# ### Dependencies: Under Mac OSX the newest version of XQuartz has to be
# installed. Free downloadat: http://xquartz.macosforge.org/landing/
# 
# ### Input: The script expects result files generated by the MosaicSuite
# particle tracker plugin in Fiji (http://mosaic.mpi-cbg.de) as input. Result
# files produced by the plugin (all trajectories to table) have to be saved as
# .txt files and stored in a directory inside the "input" directory. It should
# not be a problem to make this script accept other input formats.
# 
# ### Output: The script automatically saves dataframes and plots generated
# during the run into the output directory. Additionally, the complete
# environment.R file is saved. This file contains all variables functions etc.
# generated during the run and can be reloaded for further analysis.


# SECTION: Clean up, set working directory, load packages------------------

rm(list=ls()) # clean up

library("ggplot2")
library("plyr")
library("reshape2")
library("tcltk2")


# SECTION: Set parameters -------------------------------------------------

# Please adjust all of the following parameters

unix_win = "unix" # Are you working on a unix system (OSX, Linux) or on windows?
output_dir = tk_choose.dir(caption=paste("Select output directory (dataframes and plots will be saved here)"))
condition_1 = "test1"
condition_2 = "test2"
time_res = 1 # time resolution of image aquisition (in seconds)
min_tra_length = 15 # The minimal trajectory length; shorter tracks won't be analysed
pixelsize_x = 0.081218 # [µ/pixel] # I know it's the same in x and y, thanks!
pixelsize_y = 0.081218 # [µ/pixel] # SD2_iXon_100x = 0.081218 SD1_Neo_60x = 0.108333 
                                   # DV_coldsnap_100x = 0.06473 

text_size = 28 # sets text size in all plots
cbPalette <- c("#999999", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", 
               "#D55E00", "#CC79A7")
cbbPalette <- c("#000000", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", 
                "#D55E00", "#CC79A7")


# SECTION: Define functions -----------------------------------------------

extract = function(df){
  tra_length = nrow(df)
  time = (df$Frame * time_res)
  x = df$x * pixelsize_x
  y = df$y * pixelsize_y
  intensity = df$m0
  mean_intensity = mean(intensity)
  data.frame(tra_length, time, x, y, intensity, mean_intensity)
}

generate.df = function(condition){
  if(unix_win=="unix"){
  input_dir = tk_choose.dir(caption=paste("Select input directory for ", 
                                          condition, ".", sep=""))
  }else{
    input_dir = choose.dir(caption=paste("Select input directory for ", 
                                      condition, ".", sep=""))
  }
  setwd(input_dir)
  files = list.files(pattern = ".txt")
  assign(paste("df", condition, sep="_"), NULL)
  for(i in seq_along(files)){
    df_temp = read.delim(files[i])
    condition_tag = rep(condition, nrow(df_temp))
    id = rep(i, nrow(df_temp))
    df_temp = cbind(condition_tag, id, df_temp)
    df_temp = ddply(df_temp, .(condition_tag, id, Trajectory), extract)
    assign(paste("df", condition, sep = "_"), 
           rbind(get(paste("df", condition, sep="_")), df_temp))   
  }
  return(get(paste("df", condition, sep = "_")))
}

msd.ensemble = function(x, y){
  ensemble_msd = NULL
  for(i in 1:(length(x))){
    msd_temp = (x[i] - x[1])^2 + (y[i] - y[1])^2
    ensemble_msd = c(ensemble_msd, msd_temp)
  }
  return(ensemble_msd)
}

msd.tau = function(df){
  #browser()
  tra_length = nrow(df) # trajectory length
  # Calculate MSD_tau
  msd_tau = 0
  for(dn in 1:(tra_length/3)){ # dn (delta n) is the frameshift! 
    sum_msd_dn = NULL   
    for (n in 1:(tra_length-dn-1)){ # n is the frame
      msd_n_temp = (df$x[n+dn] - df$x[n])^2 + (df$y[n+dn] - df$y[n])^2
      sum_msd_dn =  c(sum_msd_dn, msd_n_temp)
    }
    msd_tau_dn = mean(sum_msd_dn) # mean
    msd_tau = c(msd_tau, msd_tau_dn)  
    }
  # Get diffusion coefficient D from log-log plot
  # This part is based on Sbalzarini et al. 2005,
  # (http://goo.gl/7lxkj), page 192
  #browser()
  timeshift = c(0:(tra_length/3)) * time_res
  log_timeshift = log(timeshift[2:length(timeshift)])
  log_msd_tau = log(msd_tau[2:length(msd_tau)])
  fit_log = lm(log_msd_tau ~ log_timeshift)
  log_timeshift = c(NA, log_timeshift)
  log_msd_tau = c(NA, log_msd_tau)
  coefs = coef(fit_log) #$coefficients
  alpha = coefs[[2]] # scaling coefficient
  d = 4^-1 * exp(coefs[[1]]) # diffusion coefficient
  # Get D from alternative fit
  alt_timeshift = timeshift[1:4]
  alt_msd = msd_tau[1:4]
  x = 4 * alt_timeshift
  y = alt_msd
  alt_fit = lm(y~x-1)  # -1: fit through origin
  alt_coefs = coef(alt_fit)
  alt_d = alt_coefs[[1]]
  data.frame(timeshift, msd_tau, log_timeshift, 
             log_msd_tau, d, alt_d, alpha) # alt_d
}
 
int.bin = function(intensity){
  #browser()
#   quants = as.vector(quantile(intensity))
#   int_bin = cut(intensity, 
#                 breaks=quants,
#                 include.lowest=TRUE, right=FALSE,
#                 labels=c("tiny", "small", "medium", "big")
#                 )
  mean_int_all = mean(intensity)
  min_int_all = min(intensity)
  max_int_all = max(intensity)
  # define intensity breaks (bins), cut 
  int_bin = cut(intensity, 
                breaks = c(0, 
                           mean_int_all - 2/3 * mean_int_all, 
                           mean_int_all + mean_int_all/3,
                           max_int_all), 
                include.lowest=TRUE, right=FALSE, 
                labels=c("small", "medium", "big"))
  return(int_bin)  
}

write.reload = function(filename){
  # write
  write.table(get(filename), paste(output_dir, '/', filename, 
                                   ".txt", sep=""), sep="\t")
  # reload
  assign(filename, 
         read.delim(paste(output_dir, '/', filename, ".txt", 
                          sep="")))  
}

mean.d.alpha = function(df){
  # D
  mean_d = mean(df$d)
  sd_d = sd(df$d)
  sem_d = sd_d / sqrt(nrow(df))
  # alt D
  mean_alt_d = mean(df$alt_d)
  sd_alt_d = sd(df$alt_d)
  sem_alt_d = sd_alt_d / sqrt(nrow(df))  
  # alpha
  mean_alpha = mean(df$alpha)
  sd_alpha= sd(df$alpha)
  sem_alpha = sd_alpha / sqrt(nrow(df))
  data.frame(mean_d, sd_d, sem_d, mean_alt_d, sd_alt_d, 
             sem_alt_d, mean_alpha, sd_alpha, sem_alpha)
}

save.plot = function(plot, file_name, width, height){
  setwd(output_dir)
        ggsave(p, file=file_name, width=width, height=height)
}


# SECTION: Read result files; full length trajectories only -------------
conditions = ls(pattern="condition_")
df_raw = NULL
for(i in seq_along(conditions)){
  assign(paste("df", get(conditions[i]), sep="_"), 
         generate.df(get(conditions[i])))
  df_raw = rbind(df_raw, get(paste("df", get(conditions[i]), sep="_")))
}
write.reload("df_raw")

# Only full length trajectories
df_filtered = subset(df_raw, tra_length>=min_tra_length)
write.reload("df_filtered")


# Section: Bin by intensity ----------------------------------------------

# Intensity bins are used as an approximation for particle size. 
df_binned = ddply(df_filtered, .(condition_tag), transform, 
                  int_bin=int.bin(mean_intensity))
write.reload("df_binned")


# SECTION: Compute and plot ensemble MSD -----------------------------

df_msd_ensemble = ddply(df_binned, 
                        .(condition_tag, id, Trajectory, mean_intensity),
                        transform, ensemble_msd=msd.ensemble(x, y))
write.reload("df_msd_ensemble")

# Use reshape package (melt cast and co.) to get mean ensemble_msd
df_reshape = melt(df_msd_ensemble, id=c("time", "condition_tag", "int_bin"), 
                  measure="ensemble_msd")
df_mean_msd_ensemble = dcast(df_reshape, time + condition_tag + 
                             int_bin ~ "ensemble_msd", mean)
write.reload("df_mean_msd_ensemble")

# Plot ensemble MSD
p = ggplot(df_mean_msd_ensemble, aes(x=time, y=ensemble_msd, 
                                     colour=factor(int_bin)))
#p = p + geom_point(size=5, colour="black")
p = p + geom_point(size=3)
#p = p + scale_x_continuous(limits=c(0, 6), breaks=seq(0, 6, 1))
#p = p + scale_y_continuous(limits=c(0, 0.2), breaks=seq(0, 0.25, 0.05))
p = p + facet_wrap(~condition_tag, ncol=5)
p = p + labs(x="timeshift [s]", 
             y=bquote(MSD ~ "[" ~µm^2~ "]"), colour="Intensity bin")
p = p + theme_bw(base_size=text_size)
p

save.plot(p, "msd_ensemble.pdf", 9, 5)


# SECTION: Compute and plot MSD_tau, D, alpha -----------------------------

df_msd_tau = ddply(df_binned, .(condition_tag, id, Trajectory, mean_intensity, 
                                int_bin), msd.tau, .progress="text" )
write.reload("df_msd_tau")

# Get mean MSD_tau
df_reshape = melt(df_msd_tau, id=c("timeshift", "log_timeshift", "condition_tag", 
                                   "int_bin"), 
                  measure=c("msd_tau", "log_msd_tau"), variable="log_or_not")
df_mean_msd_tau = dcast(df_reshape, timeshift + log_timeshift + 
                        condition_tag  ~ log_or_not, mean) #+ int_bin
write.reload("df_mean_msd_tau")


# Plot msd_tau against timeshift
p = ggplot(df_mean_msd_tau, aes(x=timeshift, y=msd_tau, 
                                color=factor(condition_tag))) #shape=factor(int_bin)
#p = p + stat_smooth(method="lm", formula=y~x, size=1.5)
p = p + stat_smooth(method="nls", formula=y~4*d*x^alpha, 
                    se=FALSE, start=list(d=2, alpha=2), size=1.5) # colour="black"
#p = p + geom_path(size=1.5)
p = p + geom_point(size=5, colour="black")
#p = p + scale_shape(solid = FALSE)
p = p + geom_point(size=4)
p = p + scale_colour_manual(values=cbPalette)
p = p + guides(color=FALSE)
#p = p + scale_y_continuous(limits=c(0, 0.125))
#p = p + facet_wrap(~condition_tag)
p = p + labs(x="timeshift [s]", y=bquote(MSD ~ "[" ~µm^2~ "]"))
p = p + theme_bw(base_size=text_size)
p

save.plot(p, "msd_tau_all.pdf", 9, 4)    #p, "msd_tau.pdf",5, 4.5


# Plot log_msd_tau against log_timeshift

p = ggplot(df_mean_msd_tau, aes(x=log_timeshift, y=log_msd_tau, 
                                colour=factor(condition_tag)))
p = p + stat_smooth(method = "lm", formula = y ~ x, size=1)
p = p + geom_point(size=5, colour="black")
p = p + geom_point(size=4)
p = p + scale_colour_manual(values=cbPalette)
#p = p + facet_wrap(~condition_tag)
p = p + labs(x="log dt", y="log MSD", colour="Condition")
p = p + theme_bw(base_size=text_size)
p

save.plot(p, "log_msd_tau.pdf", 9, 5)


# SECTION: Plot diffusion coefficient D and alpha -------------------------

df_temp = ddply(df_msd_tau, .(condition_tag, int_bin), mean.d.alpha)

# D against intensity
p = ggplot(df_temp, aes(x=int_bin, y=mean_d, colour=condition_tag))
p = p + geom_line(aes(group=condition_tag), size=1.5)
p = p + geom_errorbar(aes(ymin=mean_d-sem_d, ymax=mean_d+sem_d), 
                      size=1, width=0.2, colour="black")
p = p + geom_point(size=5, colour="black")
p = p + geom_point(size=4)
#p = p + facet_wrap(~condition_tag)
p = p + labs(x="Intensity", y=bquote(D ~"["~µm^2/s~"]"), colour="Condition")
p = p + theme_bw(base_size=28)
p

save.plot(p, "d_intensity.pdf", 7, 4)

# D barcharts
df_temp = ddply(df_msd_tau, .(condition_tag), mean.d.alpha) # ,intBin

# reorder, only if necessary...
#dataTemp2 = transform(dataTemp2, 
  #condition = reorder(condition, order(meanD, decreasing = TRUE)))

# D
p = ggplot(df_temp, aes(x=factor(condition_tag), y=mean_d))
p = p + geom_bar(aes(fill=factor(condition_tag)), stat="identity", 
                 width=0.7, colour="black", size=1)
p = p + geom_errorbar(aes(ymin=mean_d-sem_d, ymax=mean_d+sem_d), 
                      size=1, width=0.5)
p = p + labs(x="Condition", y=bquote(D ~"["~µm^2/s~"]"), fill="Condition")
#p = p + facet_wrap(~intBin)
p = p + theme(text = element_text(size=28),
              axis.text.x = element_text(angle = 45, hjust = 1))
p

save.plot(p, "d_condition.pdf", 7, 6)

# alt D
p = ggplot(df_temp, aes(x=factor(condition_tag), y=mean_alt_d))
p = p + geom_bar(aes(fill=factor(condition_tag)), stat="identity", 
                 width=0.7, colour="black", size=1)
p = p + geom_errorbar(aes(ymin=mean_alt_d-sem_alt_d, ymax=mean_alt_d+sem_alt_d), 
                      size=1, width=0.5)
p = p + labs(x="Condition", y=bquote(D ~"["~µm^2/s~"]"), fill="Condition")
#p = p + facet_wrap(~intBin)
p = p + theme(text = element_text(size=28),
              axis.text.x = element_text(angle = 45, hjust = 1))
p

save.plot(p, "alt_d_condition.pdf", 7, 6)


# alpha
p = ggplot(df_temp, aes(x=factor(condition_tag), y=mean_alpha))
p = p + geom_bar(aes(fill=factor(condition_tag)), stat="identity", 
                 width=0.7, colour="black", size=1)
p = p + geom_errorbar(aes(ymin=mean_alpha-sem_alpha, 
                          ymax=mean_alpha+sem_alpha), size=1, width=0.5)
p = p + labs(x="Condition", y="alpha", fill="Condition")
#p = p + facet_wrap(~intBin)
p = p + theme(text = element_text(size=28),
              axis.text.x = element_text(angle = 45, hjust = 1))
p

save.plot(p, "alpha_condition.pdf", 7, 4)


# SECTION: Scatterplot alpha against D2 --------------------------------
# Scatterplot of alpha against regular diffusion coefficient D. 
# Mainly to get an impression haw many particles are in each bin.
# Dashed lines separate type of movement regimes(alpha>1.2 active, 
# 1.2>alpha>0.8 diffusive, alpha<0.8 subdiffusive)

df_temp = ddply(df_msd_tau, .(id, Trajectory, condition_tag, int_bin, d), 
                summarise, alpha=alpha[1])

p = ggplot(df_temp, aes(x=d, y=alpha, colour=condition_tag))
p = p + geom_jitter(size=3)
p = p + scale_x_log10()
#p = p + scale_x_continuous(limits=c(10^-4, 10^-2))
p = p + geom_line(aes(y=0.8), colour="black", size=1, linetype="dashed")
p = p + geom_line(aes(y=1.2), colour="black", size=1, linetype="dashed")
#p = p + facet_wrap(~int_bin)
p = p + labs(x = bquote(D[2] ~"["~µm^2/s~"]"), y = "alpha") 
p = p + theme_bw(base_size=text_size)
p

save.plot(p, "alpha_d.pdf", 5, 4)


p = ggplot(df_temp, aes(x=condition_tag, y=alpha))
p = p + geom_jitter(size=2.5, colour="green")
#p = p + geom_jitter(size=3, colour="green")
p = p + scale_y_continuous(limits=c(0, 1.7), breaks=seq(0, 1.7, 0.2))
p = p + geom_line(aes(y=0.8), colour="black", size=1, linetype="dashed")
p = p + geom_line(aes(y=1.2), colour="black", size=1, linetype="dashed")
#p = p + facet_wrap(~int_bin)
p = p + labs(x = "Condition", y = "alpha") 
p = p + theme_bw(base_size=text_size)
p

save.plot(p, "alpha_jitter.pdf", 5, 4)


# SECTION: D against intensity --------------------------------------------

df_temp = ddply(df_msd_tau, .(condition_tag, id, Trajectory), 
                summarize, d=d[1], intensity=mean_intensity[1])

p = ggplot(df_temp, aes(x=intensity, y=d))
p = p + geom_point()
p = p + facet_wrap(~condition_tag)
p = p + labs(x="Intensity [a.u.]", y=bquote(D ~"["~µm^2/s~"]"))
p = p + theme_bw(base_size=text_size)
p

save.plot(p, "d_intensity_2.pdf", 9, 6)


# SECTION: Plot random tracks ---------------------------------------------

# Make tracks start at zero 0/0
transform = function(df){
  time = df$time
  x = df$x - df$x[1]
  y = df$y - df$y[1]
  #   kind = rep("real", nrow(df))
  #   real = cbind(time, x, y, kind)
  #   x = c(0, diff(df$xCoords))
  #   y = c(0, diff(df$yCoords))
  #   kind = rep("trans", nrow(df))
  #   trans = cbind(time, x, y, kind)
  #   tracks_temp = rbind(real, trans)
  data.frame(time, x, y)
}

tracks = ddply(df_binned, .(id, condition_tag, Trajectory, int_bin), 
               transform)

# Take samples
sample_tracks = NULL
for(i in 1:length(conditions)){
  tracks_temp = subset(tracks, condition_tag==get(conditions[i]) & 
                         int_bin=="medium")
  pool_temp = ddply(tracks_temp, .(id, Trajectory), summarize, 
                    pool_id=id[1])
  sample_temp = pool_temp[sample(1:nrow(pool_temp), 1), ]
  sample_track_temp = subset(tracks, 
                             condition_tag==get(conditions[i]) & 
                             id==sample_temp$id & 
                             Trajectory==sample_temp$Trajectory)
  sample_tracks = rbind(sample_tracks, sample_track_temp)
}

write.reload("sample_tracks")


# plot
p = ggplot(sample_tracks, aes(x=x, y=y, colour=time))
p = p + geom_path(size=2)
p = p + scale_colour_gradientn(colours=rainbow(3)) 
p = p + facet_wrap(~condition_tag, ncol=1)
p = p + labs(x="x [µm]", y="y [µm]", colour="time [s]")
p = p + theme_bw(base_size=28)
p

save.plot(p, "tracks.pdf", 6, 7)

# track_cond_2 = subset(sample_tracks, condition_tag==condition_2)
# 
# p = ggplot(track_cond_2, aes(x=x, y=y, colour=time))
# p = p + geom_path(size=2)
# p = p + scale_colour_gradientn(colours=rainbow(3)) 
# #p = p + facet_wrap(~condition_tag, ncol=1)
# p = p + labs(x="x [µm]", y="y [µm]", colour="time [s]")
# p = p + theme_bw(base_size=28)
# p
# 
# save.plot(p, "tracks_cond2.pdf", 6, 4)


# Save environment --------------------------------------------------------
save.image(paste(dir_output, folder_output, "environment.RData", sep=""))



# Testground

# df_temp = ddply(df_msd_tau, .(condition_tag), summarize, intensity=mean(mean_intensity))
# 
# p = ggplot(df_temp, aes(x=condition_tagy=d))
# p = p + geom_point()
# #p = p + facet_wrap(~condition_tag)
# p

# timeshift = test$timeshift
# msd = test$msd
# 
# x <- 4*timeshift
# y <- msd
# fit <- lm(y~x-1)
# summary(fit)
# coef(fit)
# 
# alt_fit = lm(msd ~ timeshift)
# alt_coefs = coef(alt_fit)
# alt_coefs[3]



# Statistics --------------------------------------------------------------

# # nuber of tracks n
# n_DMSO <- nrow(subset(df_alpha_D, Condition==condition_1))
# n_LatA <- nrow(subset(df_alpha_D, Condition==condition_2))   
# 
# # statistics
# v_D_DMSO <- (subset(df_alpha_D, Condition==condition_1))$D
# v_D_LatA <- (subset(df_alpha_D, Condition==condition_2))$D
# 
# var.test(v_D_DMSO, v_D_LatA)  # to test for homogenious variance, if p-value greater than 0.05, we can assume that the two variances are homogeneous
# t.test(v_D_DMSO, v_D_LatA, conf.level = 0.99, var.equal=FALSE, paired=FALSE)
# 
# v_alpha_DMSO <- (subset(df_alpha_D, Condition==condition_1))$alpha
# v_alpha_LatA <- (subset(df_alpha_D, Condition==condition_2))$alpha
# 
# var.test(v_alpha_DMSO, v_alpha_LatA)  # to test for homogenious variance, if p-value greater than 0.05, we can assume that the two variances are homogeneous
# t.test(v_alpha_DMSO, v_alpha_LatA, conf.level = 0.99, var.equal=TRUE, paired=FALSE)
# 
