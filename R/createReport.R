#' Create a quality control report (in PDF format).
#'
#' This is the main function of the package and the only thing you need to call directly if you are 
#' just interested in getting a QC report.
#' 
#' You need to provide either 
#' a) the folder name of the 'txt' output, as generated by MaxQuant or an mzTab file 
#' or b) an mzTab file as generated by the OpenMS QualityControl TOPP tool (other mzTab files will probably not work)
#' 
#' Optionally, provide a YAML configuration object, which allows to (de)activate certain plots and holds other parameters.
#' The yaml_obj is complex and best obtained by running this function once using the default (empty list).
#' A full YAML configuration object will be written in the 'txt' folder you provide and can be loaded using
#' \code{\link[yaml]{yaml.load}}.
#' 
#' The PDF and the config file will be stored in the given txt folder.
#' 
#' @note You need write access to the txt/mzTab folder!
#' 
#' For updates, bug fixes and feedback please visit \url{https://github.com/cbielow/PTXQC}.
#'
#' @param txt_folder Path to txt output folder of MaxQuant (e.g. "c:/data/Hek293/txt")
#' @param mztab_file Alternative to **txt_folder**, you can provide a single mzTab file which contains PSM, PEP and PRT tables
#' @param yaml_obj   A nested list object with configuration parameters for the report.
#'                   Useful to switch off certain plots or skip entire sections.
#' @param report_filenames Optional list with names (as generated by \code{\link{getReportFilenames}}). 
#'                         If not provided, will be created internally by calling \code{\link{getReportFilenames}}.
#' @param enable_log If TRUE all console output (including warnings and errors) is logged to the file given in **report_filenames$log_file**.
#'                   Note: warnings/errors can only be shown in either the log **or** the console, not both!
#' @return List with named filename strings, e.g. $yaml_file, $report_file etc..
#'          
#' @export
#'
createReport = function(txt_folder = NULL,
                        mztab_file = NULL,
                        yaml_obj = list(),
                        report_filenames = NULL,
                        enable_log = FALSE)
{
  if (!exists("DEBUG_PTXQC")) DEBUG_PTXQC = FALSE ## debug only when defined externally
  
  ## the following code makes sure that a plotting device is open.
  ## In some scenarios, the a plotting device is not available by default, e.g. in non-interactive sessions (e.g. shinyApps).
  ## Some versions of R then open a default pdf device to rplots.pdf, but permissions might not allow to write there - so our app crashes.
  ## In any case, a plotting device is needed for some functions calls, e.g. in grid, to determine some meta-parameters, such as font size...
  ptxqc_dummy_pdffile = tempfile(fileext=".pdf")
  pdf(ptxqc_dummy_pdffile)      ## create a real file, since the pdf(NULL) might not be able to fulfill all requests-
  ptxqc_dummy_dev = dev.cur()   ## remember the device number
  on.exit({                     # when leaving the function, close our device (avoid leaving zombies)
    if (ptxqc_dummy_dev %in% dev.list()) {
      dev.off(ptxqc_dummy_dev) 
      unlink(ptxqc_dummy_pdffile) ## delete the file; it might stay there for the whole session otherwise
    } else warning("Dummy graphics device was closed by someone else. This should not have happened...")
  }, add = TRUE)  
  
  time_start = Sys.time()
  #mztab_file = "c:\\temp\\test.mzTab"
  ##mztab_file = NULL
  
  in_count =  (!is.null(mztab_file)) + (!is.null(txt_folder))
  if ( in_count == 2 )
  {
    stop("Please provide EITHER txt_folder or mztab_file, not both")
  }
  if ( in_count == 0 )
  {
    stop("Please provide EITHER mz_folder or mztab_file. Both are currently missing!")
  }
  
  ###
  ###  prepare the YAML config
  ###
  if (!inherits(yaml_obj, "list"))
  {
    stop(paste0("Argument 'yaml_obj' is not of type list\n"));
  }
  yc = YAMLClass$new(yaml_obj)
  
  
  MZTAB_MODE = !is.null(mztab_file)  ## will be TRUE if mzTab is detected
  
  if (MZTAB_MODE)
  {
    base_folder = dirname(mztab_file)
    mzt = MzTabReader$new()
    mzt$readMzTab(mztab_file) ## creates an inital fc.raw.file mapping from MTD
    expr_fn_map = quote(mzt$fn_map)
    txt_files = NULL
  } else 
  {
    if (!any(file.info(txt_folder)$isdir, na.rm = TRUE))
    {
      stop(paste0("Argument txt_folder with value '", txt_folder, "' is not a valid directory\n"));
    }
    base_folder = txt_folder
    txt_files = list()
    txt_files$param = "parameters.txt"
    txt_files$summary = "summary.txt"
    txt_files$groups = "proteinGroups.txt"
    txt_files$evd = "evidence.txt"
    txt_files$msms = "msms.txt"
    txt_files$msmsScan = "msmsScans.txt"
    txt_files$mqpar = "mqpar.xml"
    txt_files = lapply(txt_files, function(file) file.path(txt_folder, file))
    
    ## prepare for readMQ()
    mq = MQDataReader$new()
    expr_fn_map = quote(mq$fn_map)
    
  }
  ## create names of output files (report PDF, YAML, stats, etc...)
  if (is.null(report_filenames)) {
    use_extended_reportname = yc$getYAML("PTXQC$ReportFilename$extended", TRUE)
    rprt_fns = getReportFilenames(base_folder, use_extended_reportname, mzTab_filename = mztab_file)
  } else {
    rprt_fns = report_filenames
  }
  ## read manual filename shortening & sorting (if available)  
  eval(expr_fn_map)$readMappingFile(rprt_fns$filename_sorting)
  
  ##
  ## start logging the output
  if (enable_log)
  {
    ## establish our own error handler, so we can see the traceback etc
    options(error=function(x) { 
            cat("\nTraceback:\n")
            traceback()
            cat(paste0("\nAn error occurred: '", trimws(geterrmessage()), "'. See '", rprt_fns$log_file, "' for details!\n\n\n"))})

    my_log = file(rprt_fns$log_file, open = "wt") # File name of output log
    sink(my_log, type = "output", split = TRUE) # Writing console output to log file
    sink(my_log, type = "message")  ## cannot be split ... so we need to decide where it should go

    on.exit({  
      ## show warnings, before we leave
      print(warnings());
    
      ## Restore output to console
      sink(type="message")
      sink() 
    }, add = TRUE)
  }
  

  cat(paste0(date(), ": Starting QC computation on report '", rprt_fns$report_file_prefix, "'\n"))

  ##
  ## YAML config (with default values if no yaml file was given)
  ##
  
  yc_param_lstqcMetrics_list = createYaml(yc = yc, DEBUG_PTXQC = DEBUG_PTXQC, txt_files = txt_files)
  
  yc = yc_param_lstqcMetrics_list$yc
  yaml_param = yc_param_lstqcMetrics_list$param
  lst_qcMetrics = yc_param_lstqcMetrics_list$lst_qcMetrics
  
  ## write out the final YAML file (so users can disable metrics, if they fail)
  yc$writeYAML(rprt_fns$yaml_file)
  
  out_formats_supported <- yaml_param$param_OutputFormats

  
  ## write shortnames and sorting of filenames
  eval(expr_fn_map)$writeMappingFile(rprt_fns$filename_sorting)
  
  ## get full filenames (and their suffix -- for mzQC metadata)
  file_meta = QCMetaFilenames$new()
  ## does only work if mqpar.xml is present (for now)
  if (!MZTAB_MODE) file_meta$data = getMetaFilenames(txt_files$mqpar, base_folder)
  ## --> wherever you need this data, simply re-grab the singleton using 'QCMetaFilenames$new()$data'
  
  ######
  ######  parameters.txt ...
  ######
  
  if (MZTAB_MODE) d_parAll = mzt$getParameters()
  else d_parAll = mq$readMQ(txt_files$param, type="par")
  
  lst_qcMetrics[["qcMetric_PAR"]]$setData(d_parAll)
  
  ######
  ######  summary.txt ...
  ######
  
  if (MZTAB_MODE) d_smy = mzt$getSummary()
  else d_smy = mq$readMQ(txt_files$summary, type="sm", add_fs_col = yaml_param$add_fs_col)
  #colnames(d_smy)
  #colnames(d_smy[[1]])
  
  ### MS/MS identified [%]
  lst_qcMetrics[["qcMetric_SM_MSMSIdRate"]]$setData(d_smy, yaml_param$id_rate_bad, yaml_param$id_rate_great)
  
  ### TIC
  if (MZTAB_MODE) lst_qcMetrics[["qcMetric_SM_TIC"]]$setData(d_smy)
  
  ######
  ######  proteinGroups.txt ...
  ######
  if (MZTAB_MODE) df_pg = mzt$getProteins()
  else df_pg = mq$readMQ(txt_files$groups, type="pg", col_subset=NA, filter="R")
  
  ## just a scope
  {  
    ##
    ## Raw/LFQ/Reporter intensity boxplots
    ##
    clusterCols = list()
    
    colsSIL = grepv("^intensity\\.[hlm](\\.|$)", colnames(df_pg))
    colsLF = grepv("^intensity\\..", colnames(df_pg))
    colsOneCond = "intensity" ## just one group -- we still want to know what the overall intensity is
    if (length(colsSIL)) {
      ## ignore intensity.l and alike if real groups are present
      plain_channel = grepv("^intensity\\.[hlm]$", colnames(df_pg))
      if (all(plain_channel == colsSIL)) colsW = colsSIL else colsW = setdiff(colsSIL, plain_channel)
    } else if (length(colsLF)) {
      colsW = colsLF
    }  else {
      colsW = colsOneCond
    }
    
    ## a global PG name mapping
    MAP_pg_groups = data.frame(long = colsW)
    MAP_pg_groups$short = shortenStrings(simplifyNames(delLCP(MAP_pg_groups$long, 
                                                              min_out_length = yaml_param$GL_name_min_length, 
                                                              add_dots = TRUE), 
                                                       min_out_length = yaml_param$GL_name_min_length))
    ##
    ## Contaminants plots on Raw intensity
    ##
    lst_qcMetrics[["qcMetric_PG_Cont"]]$setData(df_pg, colsW, MAP_pg_groups)
    
    
    ###
    ### Raw intensity boxplot
    ###
    
    clusterCols$raw.intensity = colsW ## cluster using intensity
    
    lst_qcMetrics[["qcMetric_PG_RawInt"]]$setData(df_pg, int_cols = colsW, MAP_pg_groups = MAP_pg_groups, thresh_intensity = yaml_param$param_PG_intThresh)
    
    ##
    ## LFQ boxplots
    ##
    colsSIL = grepv("^lfq.intensity\\.[hlm](\\.|$)", colnames(df_pg))
    colsLF = grepv("^lfq.intensity\\..", colnames(df_pg))
    
    ## a global PG name mapping
    MAP_pg_groups_LFQ = NA
    if (length(c(colsSIL, colsLF)) > 0)
    {
      if (length(colsSIL)) {
        ## unlike intensity.l, there is no lfq.intensity.l which we could remove
        colsW = colsSIL
      } else colsW = colsLF
      MAP_pg_groups_LFQ = data.frame(long = colsW)
      MAP_pg_groups_LFQ$short = shortenStrings(simplifyNames(delLCP(MAP_pg_groups_LFQ$long, 
                                                                    min_out_length = yaml_param$GL_name_min_length, 
                                                                    add_dots = TRUE), 
                                                             min_out_length = yaml_param$GL_name_min_length))
      
      clusterCols$lfq.intensity = colsW ## cluster using LFQ
      
      lst_qcMetrics[["qcMetric_PG_LFQInt"]]$setData(df_pg, colsW, MAP_pg_groups_LFQ, yaml_param$param_PG_intThresh)
    }
    
    ##
    ## iTRAQ/TMT, reporter ion intensity boxplot
    ##
    ## either "reporter.intensity.0.groupname" or "reporter.intensity.0" (no groups)    
    colsITRAQ = grepv("^reporter.intensity.[0-9]", colnames(df_pg)) ## we require at least one number!
    ## a global PG name mapping
    MAP_pg_groups_ITRAQ = NA
    if (length(colsITRAQ) > 0)
    {
      MAP_pg_groups_ITRAQ = data.frame(long = c(colsITRAQ))
      MAP_pg_groups_ITRAQ$short = shortenStrings(simplifyNames(delLCP(MAP_pg_groups_ITRAQ$long, 
                                                                      min_out_length = yaml_param$GL_name_min_length, 
                                                                      add_dots = TRUE), 
                                                               min_out_length = yaml_param$GL_name_min_length))
      
      clusterCols$reporter.intensity = colsITRAQ ## cluster using reporters
      
      lst_qcMetrics[["qcMetric_PG_ReporterInt"]]$setData(df_pg, colsITRAQ, MAP_pg_groups_ITRAQ, yaml_param$param_PG_intThresh)
    }
    
    
    ##
    ## PCA
    ##
    ## some clustering (its based on intensity / lfq.intensity columns..)
    ## todo: maybe add ratios -- requires loading from txt though..
    MAP_pg_groups_ALL = rbind(MAP_pg_groups, MAP_pg_groups_LFQ, MAP_pg_groups_ITRAQ)
    
    lst_qcMetrics[["qcMetric_PG_PCA"]]$setData(df_pg, clusterCols, MAP_pg_groups_ALL)
    
    
    ##################################
    ## ratio plots
    ##################################
    ## get ratio column
    ratio_cols = grepv("^ratio\\.[hm]\\.l", colnames(df_pg))  ## e.g. "ratio.m.l.ARK5exp" or "ratio.m.l.variability.ARK5exp"
    ## remove everything else
    ## e.g. we do not want ratio.h.l.variability.ARK5exp, i.e. the 'variability' property
    ratio_cols = grepv("^ratio.[hm].l.normalized", ratio_cols, invert = TRUE)
    ratio_cols = grepv("^ratio.[hm].l.count", ratio_cols, invert = TRUE)
    ratio_cols = grepv("^ratio.[hm].l.variability", ratio_cols, invert = TRUE)
    ratio_cols = grepv("^ratio.[hm].l.significance.a", ratio_cols, invert = TRUE) ## from MQ 1.0.1x
    ratio_cols = grepv("^ratio.[hm].l.significance.b", ratio_cols, invert = TRUE)
    ratio_cols = grepv("^ratio.[hm].l.iso.count", ratio_cols, invert = TRUE) ## from MQ 1.5.1.2
    ratio_cols = grepv("^ratio.[hm].l.type", ratio_cols, invert = TRUE)
    ratio_cols
    
    if (length(ratio_cols) > 0)
    {
      lst_qcMetrics[["qcMetric_PG_Ratio"]]$setData(df_pg, ratio_cols = ratio_cols, thresh_LabelIncorp = yaml_param$pg_ratioLabIncThresh, GL_name_min_length = yaml_param$GL_name_min_length)
    }
  }
  
  ######
  ######  evidence.txt ...
  ######
  
  ## protein.names is only available from MQ 1.4 onwards
  if (MZTAB_MODE) {
    all_evd = mzt$getEvidence()
    df_evd = all_evd$genuine
    df_evd_tf = all_evd$transferred
    
  }
  else {
    all_evd = mq$readMQ(txt_files$evd, type="ev", filter="R",
                        col_subset=c("proteins",
                                     numeric = "Retention.Length",
                                     numeric = "retention.time.calibration", 
                                     numeric = "Retention.time$", 
                                     numeric = "Match.Time.Difference",
                                     numeric = "^intensity$", 
                                     "^Type$",
                                     numeric = "Mass\\.Error", 
                                     numeric = "^uncalibrated...calibrated." ,
                                     numeric = "^m.z$",
                                     numeric = "^score$", 
                                     numeric = "^fraction$",  ## only available when fractions were given
                                     "Raw.file", 
                                     "^Protein.Group.IDs$", 
                                     "Contaminant",
                                     "^modifications$",
                                     numeric = "^Charge$", 
                                     "modified.sequence",
                                     numeric = "^Mass$",
                                     "^protein.names$",
                                     numeric = "^ms.ms.count$",
                                     numeric = "^reporter.intensity.", ## we want .corrected and .not.corrected
                                     numeric = "Missed\\.cleavages",
                                     "^sequence$")) 
    ## contains NA if 'genuine' ID
    ## ms.ms.count is always 0 when mtd has a number; 'type' is always "MULTI-MATCH" and ms.ms.ids is empty!
    #dsub = d_evd[,c("ms.ms.count", "match.time.difference")]
    #head(dsub[is.na(dsub[,2]),])
    #sum(0==(dsub[,1]) & is.na(dsub[,2]))
    ##
    ## MQ1.4 MTD is either: NA or a number
    ##
    if (!is.null(all_evd)) all_evd$is.transferred = (all_evd$type == "MULTI-MATCH")
    
    df_evd = all_evd[all_evd$type != "MULTI-MATCH", ]
    df_evd_tf = all_evd[all_evd$type == "MULTI-MATCH", , drop=FALSE] ## keep columns, if empty
    
  }
  ## just a local scope to fold evidence metrics in the editor...
  {
    if (!checkEnglishLocale(df_evd)){
      stop ("\n\nThe data in evidence.txt looks weird! MaxQuant was run under a wrong locale/region settings (i.e. make sure to use an english locale, specifically, the decimal separator should be '.'!). Please fix the locale on the PC where MaxQuant was used, and redo the computation.\n\n")
    } 
    
    ### warn of special contaminants!
    if (inherits(yaml_param$yaml_contaminants, "list"))  ## SC are requested
    {
      if (!is.null(df_pg))
      {
        lst_qcMetrics[["qcMetric_EVD_UserContaminant"]]$setData(df_evd, df_pg, yaml_param$yaml_contaminants)
      } else {
        lst_qcMetrics[["qcMetric_EVD_UserContaminant"]]$setData(df_evd, NULL, yaml_param$yaml_contaminants)
      }
    }
   
    ##
    ## intensity of peptides
    ##
    lst_qcMetrics[["qcMetric_EVD_PeptideInt"]]$setData(df_evd, yaml_param$param_EV_intThresh)
    
    ##
    ## MS2/MS3 labeled (TMT/ITRAQ) only: reporter intensity of peptides
    ##
    lst_qcMetrics[["qcMetric_EVD_ReporterInt"]]$setData(df_evd)
    
    
    ##
    ## Variable modification frequencies
    ##
    lst_qcMetrics[["qcMetric_EVD_modTable"]]$setData(df_evd)
    
    
    
    ##
    ## peptide & protein counts
    ##
    lst_qcMetrics[["qcMetric_EVD_ProteinCount"]]$setData(df_evd, df_evd_tf, yaml_param$param_EV_protThresh)
    
    lst_qcMetrics[["qcMetric_EVD_PeptideCount"]]$setData(df_evd, df_evd_tf, yaml_param$param_EV_pepThresh)
    
    ####
    #### peak length (not supported in MQ 1.0.13)
    ####
    if ("retention.length" %in% colnames(df_evd))  
    {
      lst_qcMetrics[["qcMetric_EVD_RTPeakWidth"]]$setData(df_evd)
      #lst_qcMetrics[["qcMetric_EVD_CarryOver"]]$setData(df_evd)
    } ## end retention length (aka peak width)
    
    ##
    ## retention time calibration (to see if window was sufficiently large)
    ## (not supported in MQ 1.0.13)  
    ## Even if MBR=off, this column always contains numbers (usually 0, or very small)
    ##
    
    if ("retention.time.calibration" %in% colnames(df_evd))
    {
      ## this should enable us to decide if MBR was used (we could also look up parameters.txt -- if present)
      if (!(yaml_param$param_evd_mbr == FALSE) & nrow(df_evd_tf)>0)
      {
        lst_qcMetrics[["qcMetric_EVD_MBRAlign"]]$setData(df_evd, 
                                                         tolerance_matching = yaml_param$param_EV_MatchingTolerance, 
                                                         raw_file_mapping = eval(expr_fn_map)$raw_file_mapping)
        
        ### 
        ###     MBR: ID transfer
        ###
        #debug (restore data): lst_qcMetrics[["qcMetric_EVD_RTPeakWidth"]]$setData(df_evd)
        avg_peak_width = lst_qcMetrics[["qcMetric_EVD_RTPeakWidth"]]$outData[["avg_peak_width"]]
        if (is.null(avg_peak_width)) {
          warning("RT peak width module did not run, but is required for MBR metrics. Enable it and try again or switch off MBR metrics!")
        } else lst_qcMetrics[["qcMetric_EVD_MBRIdTransfer"]]$setData(df_evd, df_evd_tf, avg_peak_width)
        
        
        ##
        ## MBR: Tree Clustering (experimental)
        ##  and
        ## MBR: additional evidence by matching MS1 by AMT across files
        ##
        lst_qcMetrics[["qcMetric_EVD_MBRaux"]]$setData(all_evd)
        
      } ## MBR has data
    } ## retention.time.calibration column exists
    
    
    ##
    ## charge distribution
    ##
    ##  (this uses genuine peptides only -- no MBR!)
    ## 
    lst_qcMetrics[["qcMetric_EVD_Charge"]]$setData(df_evd)
    
    ##
    ## peptides per RT
    ##
    lst_qcMetrics[["qcMetric_EVD_IDoverRT"]]$setData(df_evd)
    
    
    ##
    ## upSet plot
    ##
    lst_qcMetrics[["qcMetric_EVD_UpSet"]]$setData(df_evd)
    
    ##
    ## barplots of mass error
    ##
    ## MQ seems to mess up mass recal on some (iTRAQ/TMT) samples, by reporting ppm errors which include modifications
    ## , thus one sees >1e5 ppm, e.g. 144.10 Da
    ##  this affects both 'uncalibrated.mass.error..ppm.'   and
    ##                    'mass.error..ppm.'
    ## HOWEVER, 'uncalibrated...calibrated.m.z..ppm.' seems unaffected, but is not available in all MQ versions :(
    ##    also, 'mass' and 'm/z' columns seem unaffected.
    ## We cannot always reconstruct mass_error[ppm] from 'm/z' and mass columns 
    ## since 'm/z' is just too close to the theoretical value or islacking precision of the stored numbers.
    ##
    ## The MQ list reports one case with high ppm error (8000), where the KR.count was at fault. We cannot
    ## reconstruct this.
    ##
    ## Also, MaxQuant will not report uncalibrated mass errors if the data are too sparse for a given Raw file.
    ## Then, 'uncalibrated.mass.error..ppm.' will be 'NaN' throughout -- but weirdly, calibrated masses will be reported.
    ##
    
    ##
    ## MS1-out-of-calibration (i.e. the tol-window being too small)
    ##
    ## additionally use MS2-ID rate (should be below 1%)
    df_idrate = d_smy[, c("fc.raw.file", "ms.ms.identified....")] ## returns NULL if d_smy == NULL
    
    lst_qcMetrics[["qcMetric_EVD_PreCal"]]$setData(df_evd, df_idrate, yaml_param$param_EV_PrecursorTolPPM, yaml_param$param_EV_PrecursorOutOfCalSD)
    
    
    ##
    ## MS1 post calibration
    ##
    lst_qcMetrics[["qcMetric_EVD_PostCal"]]$setData(df_evd, df_idrate, yaml_param$param_EV_PrecursorTolPPM, yaml_param$param_EV_PrecursorOutOfCalSD, yaml_param$param_EV_PrecursorTolPPMmainSearch)
    
    
    ##
    ## Top5 contaminants
    ##
    lst_qcMetrics[["qcMetric_EVD_Top5Cont"]]$setData(df_evd)
    
    ##
    ## Oversampling: determine peaks repeatedly sequenced
    ##
    lst_qcMetrics[["qcMetric_EVD_MS2OverSampling"]]$setData(df_evd)
    
    ##
    ## missing values
    ##
    lst_qcMetrics[["qcMetric_EVD_MissingValues"]]$setData(df_evd)
    
    ## trim down to the absolute required (we need to identify contaminants in MSMS.txt later on)
    ## --> use %in% because some columns, e.g. 'missed.cleavages' are optional
    if (!DEBUG_PTXQC) df_evd = df_evd[, names(df_evd) %in% c("id", "contaminant", "fc.raw.file", "sequence", "missed.cleavages")]
  }
  
  
  
  
  ######
  ######  msms.txt ...
  ######
  
  if (MZTAB_MODE) df_msms = mzt$getMSMSScans(identified_only = TRUE)
  else df_msms = mq$readMQ(txt_files$msms, type="msms", filter = "", col_subset=c(numeric = "Missed\\.cleavages",
                                                                                  "^Raw.file$",
                                                                                  "^mass.deviations",
                                                                                  "^masses$",
                                                                                  "^mass.analyzer$",
                                                                                  "^sequence$",
                                                                                  "fragmentation",
                                                                                  "reverse",
                                                                                  numeric = "^evidence.id$"
  ), check_invalid_lines = FALSE)
  ## just a scope
  {
    ### missed cleavages (again)
    ### this is the real missed cleavages estimate ... but slow
    #df_msms_s = mq$readMQ(txt_files$msms, type="msms", filter = "", nrows=10)
    #colnames(df_msms_s)
    #head(df_msms)
    
    ##
    ##  MS2 fragment decalibration
    ##
    lst_qcMetrics[["qcMetric_MSMS_MSMSDecal"]]$setData(df_msms, eval(expr_fn_map)$raw_file_mapping$to)
    
    ##
    ## missed cleavages per Raw file
    ##
    # df_evd can be NULL; that's no problem
    lst_qcMetrics[["qcMetric_MSMS_MissedCleavages"]]$setData(df_msms, df_evd)
   
    # In case missed.cleavages is not in msms but in evd 
    # metric checks if it was already done  
    lst_qcMetrics[["qcMetric_MSMS_MissedCleavages"]]$setData(df_evd)
    
    
    
  }
  ## save RAM: msms.txt is not required any longer
  if (!DEBUG_PTXQC) rm(df_msms)
  if (!DEBUG_PTXQC) rm(df_evd)
  
  
  
  ######
  ######  msmsScans.txt ...
  ######
  if (MZTAB_MODE) df_msmsScans = mzt$getMSMSScans(identified_only = FALSE) else
     df_msmsScans = mq$readMQ(txt_files$msmsScan, type = "msms_scans", filter = "", 
                                col_subset = c(numeric = "^ion.injection.time", 
                                               numeric = "^retention.time$", 
                                               "^Identified", 
                                               numeric = "^Scan.event.number", 
                                               numeric = 'Scan.index',    ## required for fixing scan.event.number, in case its broken
                                               numeric = 'MS.scan.index', ## required for fixing scan.event.number, in case its broken
                                               "^total.ion.current",
                                               "^base.?peak.intensity", ## basepeak.intensity (MQ1.2) and base.peak.intensity (MQ1.3+)
                                               "^Raw.file",
                                               "^dp.aa$",
                                               "^dp.modification$"),
                                check_invalid_lines = FALSE)
  
  # just a scope  
  {
    ##
    ## MQ version 1.0.13 has very rudimentary MSMSscans.txt, with no header, so we need to skip the metrics of this file
    ##
    if (!is.null(df_msmsScans) && ncol(df_msmsScans) > 3)
    {
      # round RT to 2 min intervals
      df_msmsScans$rRT = round(df_msmsScans$retention.time/2)*2
      
      ##
      ## TopN over RT
      ##
      lst_qcMetrics[["qcMetric_MSMSScans_TopNoverRT"]]$setData(df_msmsScans)
      
      ##
      ## Injection time over RT
      ##
      lst_qcMetrics[["qcMetric_MSMSScans_IonInjTime"]]$setData(df_msmsScans, yaml_param$param_MSMSScans_ionInjThresh)
      
      ##
      ## MS/MS intensity (TIC and base peak)
      ##
      lst_qcMetrics[["qcMetric_MSMSScans_MSMSIntensity"]]$setData(df_msmsScans)
      
      ##
      ## TopN counts
      ##
      lst_qcMetrics[["qcMetric_MSMSScans_TopN"]]$setData(df_msmsScans)
      
      ##
      ## Scan event: % identified
      ##
      lst_qcMetrics[["qcMetric_MSMSScans_TopNID"]]$setData(df_msmsScans)
      
      ##
      ## Dependent peptides (no score)
      ##
      if ("dp.modification" %in% colnames(df_msmsScans)) {
        lst_qcMetrics[["qcMetric_MSMSScans_DepPep"]]$setData(df_msmsScans)
      }
      
    } ## end MSMSscan from MQ > 1.0.13
    
    
  }
  ## save RAM: msmsScans.txt is not required any longer
  if (!DEBUG_PTXQC) rm(df_msmsScans)
  
  #####################################################################
  #####################################################################
  ## write mzQC file
  try( ## if not enough metrics are produced, then writing will fail (e.g. one run or setQuality needs to be present)
    rmzqc::writeMZQC(
      rprt_fns$mzQC_file, 
      assembleMZQC(lst_qcMetrics, raw_file_mapping = eval(expr_fn_map)$raw_file_mapping)
    )
  )
  
  
  #####################################################################
  ## list of qcMetric objects
  print("#Metrics: ")
  print(length(lst_qcMetrics))
  
  hm = getQCHeatMap(lst_qcMetrics, raw_file_mapping = eval(expr_fn_map)$raw_file_mapping)
  #print(hm[["plot"]])
  write.table(hm[["table"]], file = rprt_fns$heatmap_values_file, quote = TRUE, sep = "\t", row.names = FALSE)
  
  ## get MQ short name mapping plot (might be NULL if no mapping was required)
  pl_nameMapping = eval(expr_fn_map)$plotNameMapping()
  
  ##
  ## plot it!!!
  ##
  cat("Creating Report file ...")
  
  #
  #param_OutputFormats = "html pdf"
  #
  out_formats = unlist(strsplit(yaml_param$param_OutputFormats, "[ ,]+"))
  out_formats
  out_format_requested = out_formats_supported[match(out_formats, out_formats_supported)]
  if (any(is.na(out_format_requested)))
  {
    stop("Output format(s) not supported: '", paste(out_formats[is.na(out_format_requested)], collapse="', '"), "'")
  }
  
  ## a bit hacky, but we want gridExtra plots to plot when we call print() -- similar to ggplot's print
  print.gtable = function(t) { plot(t)}
  
  if ("html" %in% out_format_requested)
  {
    if (rmarkdown::pandoc_available()) {
      ## HTML reports require Pandoc for converting Markdown to Html via the rmarkdown package
      if (DEBUG_PTXQC) {
        html_template = paste0(getwd(), "/inst/reportTemplate/PTXQC_report_template.Rmd")
        if (!file.exists(html_template)) stop("Wrong working directory. Please set your working directory to the PTXQC main dir such that 'paste0(getwd(), '/inst/reportTemplate/PTXQC_report_template.Rmd')' is a valid file.")
      } else {
        html_template = system.file("./reportTemplate/PTXQC_report_template.Rmd", package="PTXQC")
      }
      cat(paste0("HTML TEMPLATE: ", html_template, "\n"))
      out_dir = dirname(rprt_fns$report_file_HTML)
      file.copy(html_template, out_dir, overwrite = FALSE)
      out_template = file.path(out_dir, basename(html_template))
      ## Rmarkdown: convert to Markdown, and then to HTML (or PDF) ...
      ## Intermediates_dir is required if inputdir!=outputdir, since Shiny server might not allow write-access to input file directory
      res_html = try(
        rmarkdown::render(out_template, output_file = rprt_fns$report_file_HTML) #, intermediates_dir = dirname(rprt_fns$report_file_HTML))
      )
      if (inherits(res_html, "try-error")) {
        warning("Creating the HTML template did not succeed, probably due to an outdated markdown template the in
                txt folder. PTXQC will use the default template now instead. Fix or remove the broken/old .Rmd file from the ", txt_folder, 
                " to avoid this warning.", immediate. = TRUE)
        rmarkdown::render(html_template, output_file = rprt_fns$report_file_HTML) #, intermediates_dir = dirname(rprt_fns$report_file_HTML))
      } 
   } else {
      warning("The 'Pandoc' converter is not installed on your system or you do not have read-access to it!\n",
              "Pandoc is required for HTML reports.\n",
              "Please install Pandoc <http://pandoc.org/installing.html> or make sure you have access to pandoc(.exe).\n",
              "Restart your R-session afterwards.",
              immediate. = TRUE)
    }
  }
  
  if ("plainPDF" %in% out_format_requested)
  {
    report_file_PDF = rprt_fns$report_file_PDF
    ## give the user a chance to close open reports which are currently blocked for writing
    if (!wait_for_writable(report_file_PDF))
    {
      stop("Target file not writable")
    }
    
    if (yaml_param$param_PageNumbers == "on")
    {
      printWithPage = function(gg_obj, page_nr, filename = report_file_PDF)
      {
        filename = basename(filename)
        printWithFooter(gg_obj, bottom_left = filename, bottom_right = page_nr)
      }
    } else {
      ## no page number and filename at bottom of each page
      printWithPage = function(gg_obj, page_nr, filename = report_file_PDF)
      {
        print(gg_obj)
      }
    }
    cat("\nCreating PDF ...\n")
    grDevices::pdf(report_file_PDF)
    printWithPage(hm[["plot"]], "p. 1")      # summary heatmap
    printWithPage(pl_nameMapping$plots, "p. 2")    # short file mapping
    pc = 3; ## subsequent pages start at #4
    for (qcm in lst_qcMetrics)
    {
      for (p in qcm$plots)
      {
        printWithPage(p, paste("p.", pc))
        pc = pc + 1
      }
    }
    grDevices::dev.off();
    cat(" done\n")
  }
  
  ## save plot object (for easier access, in case someone wants high-res plots)
  ## (...disabled for now until concrete use case pops up)
  #cat("Dumping plot objects as Rdata file ...")
  #save(file = rprt_fns$R_plots_file, list = "GPL")
  #cat(" done\n")

  ## output plots to global environment for editing
  cat("Dumping lst_qcMetrics to global environment...") 
  list2env(lst_qcMetrics, envir = .GlobalEnv) 
  cat(" done\n")

  ## write shortnames and sorting of filenames (again)
  eval(expr_fn_map)$writeMappingFile(rprt_fns$filename_sorting)
  
  cat(paste("Report file created at\n\n    ", rprt_fns$report_file_prefix, ".*\n\n", sep=""))
  cat(paste0("\n\nTime elapsed: ", round(as.double(Sys.time() - time_start, units="mins"), 1), " min\n\n"))


  ## return path to PDF report and YAML config, etc
  return(rprt_fns)
}
