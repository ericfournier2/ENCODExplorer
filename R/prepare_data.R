
#' Create the list of data.table for the tables in ENCODE
#' 
#' @return is a \code{list} with selected tables from ENCODE.
#'
#' @param database_filename The name of the file to save the database into.
#' @param types The names of the tables to extract using the ENCODE rest api.
#' @param overwrite If database_filename already exists, should it be overwritten?
#'   Default: \code{FALSE}.
#' 
#' @examples
#' prepare_ENCODEdb(database_filename = "tables.RDA", types = "platform")
#' file.remove("platform.RDA")
#'     \dontrun{
#'         prepare_ENCODEdb("ENCODEdb.RDA")
#'     }
#'     
#' @import data.table
#' @export
prepare_ENCODEdb <- function(database_filename = "tables.RDA",
                             types = get_encode_types(), overwrite = FALSE) {
  if(file.exists(database_filename) && !overwrite) {
    warning(paste0("The file ", database_filename, " already exists and will not be overwritten.\n",
                   "Please delete it or set overwrite = TRUE before re-running the data preparation"))
    NULL
  } else {
    # Extract the tables from the ENCODE rest api
    extract_type <- function(type) {
      cat("Extracting table", type, "\n")
      table <- extract_table(type)
      if(ncol(table) == 0) {
        return(NULL)
      }
      cat("Cleaning table", type, "\n")
      table_clean <- clean_table(table)
    }
    # List of data.frame
    tables <- lapply(types, extract_type)
    
    # Return the named tables
    names(tables) <- types
    tables[sapply(tables, is.null)] <- NULL
    tables <- lapply(tables, as.data.table)
    save(tables, file=database_filename)
   
    # Extract data from the DB
    if(length(tables) > 0) {
      invisible(tables)
    }
    else
    {
      warning(paste0("Something went wrong during data preparation. ",
                     "Please erase the database ", database_filename, " and re-run the whole process.",
                     "If the problem persists, please contact us"))
      NULL
    }
    
  }
}

#' Extract file metadata from the full set of ENCODE metadata tables.
#'
#' @return a \code{data.table} containing relevant metadata for all
#'   ENCODE files.
#'
#' @param database_filename A list of ENCODE metadata tables as loaded by
#'   prepare_ENCODEdb.
#'
#' @examples
#'     \dontrun{
#'         tables = prepare_ENCODEdb()
#'         export_ENCODEdb_matrix_lite(database_filename = tables)
#'     }
#' @import parallel
export_ENCODEdb_matrix_lite <- function(database_filename) {
  db = database_filename
  encode_df = db$file
  
  # Renaming certain column.
  encode_df <- rename_file_columns(encode_df)
  encode_df <- split_dataset_column(files = encode_df)
  
  # Merge sample information from other tables.
  encode_df <- update_project_platform_lab(files = encode_df, awards = db$award, 
                                           labs = db$lab, platforms = db$platform)
  encode_df <- update_replicate(files = encode_df, replicates = db$replicate)
  encode_df <- update_antibody(files = encode_df, antibody_lot = db$antibody_lot,
                               antibody_charac = db$antibody_characterization)
  encode_df <- update_treatment(files = encode_df, treatments = db$treatment,
                               libraries = db$library, biosamples = db$biosample,
                               replicates = db$replicate, datasets=db$dataset)
  encode_df = update_experiment(files=encode_df, experiments=db$experiment)
  encode_df = update_biosample_types(files=encode_df, biosample_types=db$biosample_type)
  encode_df = update_target(files=encode_df, targets=db$target, organisms=db$organism)
                 

  # Fetch some additional miscellaneous columns.                 
  encode_df$nucleic_acid_term = pull_column(encode_df, db$library, "replicate_libraries", "id", "nucleic_acid_term_name")
  encode_df$submitted_by <- pull_column_merge(encode_df, db$user, "submitted_by", "id", "title", "submitted_by")
  encode_df$status <- pull_column_merge(encode_df, db$dataset, "accession", "accession", "status", "status")
  encode_df <- file_size_conversion(encode_df)
  
  # Remove remaining ID prefixes
  encode_df$replicate_libraries <- remove_id_prefix(encode_df$replicate_libraries)                               
  encode_df$controls <- remove_id_prefix(encode_df$controls)
  encode_df$controlled_by <- remove_id_prefix(encode_df$controlled_by)
  encode_df$replicate_list <- remove_id_prefix(encode_df$replicate_list)
  
  # Ordering the table by the accession column
  encode_df <- encode_df[order(accession),]
  
  # Reordering the table, we want to have the column below as the first column
  # to be display fellowed by the rest the remaining column available.
  main_columns <- c("accession", "file_accession", "file_type", "file_format",
                    "file_size", "output_category", "output_type", "target", "investigated_as",
                    "nucleic_acid_term", "assay", "treatment_id", "treatment", "treatment_amount",
                    "treatment_amount_unit", "treatment_duration", "treatment_duration_unit",
                    "treatment_temperature", "treatment_temperature_unit", "treatment_notes",
                    "biosample_id", "biosample_type", "biosample_name", 
                    "dataset_biosample_summary", "dataset_description",
                    "replicate_libraries", "replicate_antibody", "antibody_target",
                    "antibody_characterization", "antibody_caption", 
                    "organism", "dataset_type", "assembly","status", 'controls', "controlled_by",
                    "lab","run_type", "read_length", "paired_end",
                    "paired_with", "platform", "href", "biological_replicates",
                    "biological_replicate_number","technical_replicate_number","replicate_list",
                    "technical_replicates", "project", "dataset", "dbxrefs", "superseded_by",
                    "file_status", "submitted_by", "library", "derived_from",
                    "file_format_type", "file_format_specifications", "genome_annotation",
                    "external_accession", "date_released", "biosample_ontology", "md5sum")

  ext_col_1 <- c("notes", "cloud_metadata.url", "s3_uri")
  ext_col_2 <- c("date_created", "uuid",  "cloud_metadata.md5sum_base64", "quality_metrics", "content_md5sum")
  all_explicit_columns = c(main_columns, ext_col_1, ext_col_2)
  other_columns = setdiff(colnames(encode_df), all_explicit_columns)
  
  # Protect against columns that might no longer part of the ENCODE metadata.
  
  missing_columns = setdiff(all_explicit_columns, colnames(encode_df))
  if(length(missing_columns) != 0) {
      message("Some expected columns are no longer present within ENCODE metadata.")
      message("Missing columns: ", paste(missing_columns, collapse=", "))
  }
  
  encode_df_lite = encode_df[,intersect(main_columns, colnames(encode_df)), with=FALSE]
  encode_df_ext_1 = encode_df[,intersect(ext_col_1, colnames(encode_df)), with=FALSE]
  encode_df_ext_2 = encode_df[,intersect(ext_col_2, colnames(encode_df)), with=FALSE]
  encode_df_ext_3 = encode_df[,other_columns, with=FALSE]

  return(list(encode_df=encode_df_lite, 
              encode_df_ext_1=encode_df_ext_1, 
              encode_df_ext_2=encode_df_ext_2, 
              encode_df_ext_3=encode_df_ext_3))
}

#' Extract file metadata from the full set of ENCODE metadata tables.
#'
#' @return a \code{data.table} containing relevant metadata for all
#'   ENCODE files.
#'
#' @param database_filename A list of ENCODE metadata tables as loaded by
#'   prepare_ENCODEdb.
#'
#' @examples
#'     \dontrun{
#'         tables = prepare_ENCODEdb()
#'         export_ENCODEdb_matrix(database_filename = tables)
#'     }
#' @import parallel
#' 
#' @export
export_ENCODEdb_matrix <- function(database_filename) {
    split_df = export_ENCODEdb_matrix_lite(database_filename)
    return(cbind(split_df[["encode_df"]], 
                 split_df[["encode_df_ext_1"]],
                 split_df[["encode_df_ext_2"]],
                 split_df[["encode_df_ext_3"]]))
}


full_db_cache_env=new.env()
#' Concatenates all available file metadata into a single data table.
#'
#' @return a \code{data.table} containing relevant metadata for all
#'   ENCODE files.
#'
#' @examples
#'     my_full_encode_df = get_encode_df_full()
#' @export
get_encode_df_full <- function() {
    if(!exists("full_db_cache", envir=full_db_cache_env)) {
        full_db = cbind(ENCODExplorer::encode_df, 
                 ENCODExplorer::encode_df_ext_1,
                 ENCODExplorer::encode_df_ext_2,
                 ENCODExplorer::encode_df_ext_3)
                 
        assign("full_db_cache", full_db, envir=full_db_cache_env)  
    }
    
    return(get("full_db_cache", envir=full_db_cache_env))
}

#' Returns a "light" version of ENCODE file metadata.
#'
#' @return a \code{data.table} containing the most relevant 
#'   metadata for all ENCODE files.
#'
#' @examples
#'     my_encode_df = get_encode_df()
#' @export
get_encode_df <- function() {
    return(ENCODExplorer::encode_df)
}

pull_column_id <- function(ids, table2, id2, pulled_column) {
    return(table2[[pulled_column]][match(ids, table2[[id2]])])
}

# Matches the entries of table1 to table2, using id1 and id2, then returns
# the values from pulled_column in table2.
pull_column <- function(table1, table2, id1, id2, pulled_column) {
  return(pull_column_id(table1[[id1]], table2, id2, pulled_column))
}

# Matches the entries of table1 to table2, using id1 and id2, then returns
# a merged vector containing the values from pulled_column in table2 when
# a match exists, or table1$updated_value if it does not.
pull_column_merge <- function(table1, table2, id1, id2, pulled_column, updated_value) {
  retval = pull_column(table1, table2, id1, id2, pulled_column)
  retval = ifelse(is.na(match(table1[[id1]], table2[[id2]])), table1[[updated_value]], retval)
  return(retval)
}

# Matches the entries of table1 to table2, using id1 and id2,
# then creates a new data.table from the column pairings described in
# value_pairs. Ex: c("antibody_target"="target") will create a column
# named "antibody_target" from table2$target. (Similar to dplyr::*_join)
pull_columns <- function(table1, table2, id1, id2, value_pairs) {
    retval <- NULL
    for(i in 1:length(value_pairs)) {
        value_name = value_pairs[i]
        out_name = ifelse(is.null(names(value_pairs)), value_name, names(value_pairs)[i])
        out_name = ifelse(out_name=="", value_name, out_name)
        if(is.null(retval)) {
            retval = data.table::data.table(pull_column(table1, table2, id1, id2, value_name))
            colnames(retval) = out_name
        } else {
            retval[[out_name]] = pull_column(table1, table2, id1, id2, value_name)
        }
    }
    return(retval)
}

# Calls pull_columns, and append the results to table1.
pull_columns_append <- function(table1, table2, id1, id2, value_pairs) {
    pulled_columns = pull_columns(table1, table2, id1, id2, value_pairs)
    return(cbind(table1, pulled_columns))
}

# Remove the type prefix from ENCODE URL-like identifiers.
# Example: /files/ENC09345TXW/ becomes ENC09345TXW.
remove_id_prefix <- function(ids) {
    return(gsub("/.*/(.*)/", "\\1", ids))
}

# Pulls a column. If no match is found, remove the ENCODE id type prefix
# from the previous value.
pull_column_no_prefix <- function(table1, table2, id1, id2, pull_value, prefix_value) {
    pulled_val = pull_column(table1, table2, id1, id2, pull_value)
    no_prefix = remove_id_prefix(table1[[prefix_value]])
    return(ifelse(is.na(pulled_val), no_prefix, pulled_val))
}

# Rename certain columns from the files table.
rename_file_columns <- function(files){
  names(files)[names(files) == 'status'] <- 'file_status'
  names(files)[names(files) == 'accession'] <- 'file_accession'
  names(files)[names(files) == 'award'] <- 'project'
  names(files)[names(files) == 'replicate'] <- 'replicate_list'
  
  return(files)
}

# Fetch information from the ENCODE award, lab and platform tables
# and merge them into encode_df (ENCODE's file table)
update_project_platform_lab <- function(files, awards, labs, platforms){
  # Updating files$project with awards$project
  files$project = pull_column_no_prefix(files, awards, "project", "id", "project", "project")
  
  # Updating files$paired_with
  files$paired_with <- remove_id_prefix(files$paired_with)
  
  # Updating files$platform with platform$title
  files$platform = pull_column_no_prefix(files, platforms, "platform", "id", "title", "platform")
  
  # Updating files$lab with labs$title
  files$lab = pull_column_no_prefix(files, labs, "lab", "id", "title", "lab")

  return(files)
}

# Fetches columns from ENCODE experiment table and merges them
# with encode_df (ENCODE's file table).
update_experiment <- function(files, experiments) {
  exp_colmap = c("target", "date_released", "status", "assay"="assay_title", "biosample_ontology",
                 "controls"="possible_controls", "dataset_biosample_summary"="biosample_summary",
                 "dataset_description"="description")
  files = pull_columns_append(files, experiments, "accession", "accession", exp_colmap)
  
  return(files)
}

# Fetches columns from ENCODE biosamples table and merges them
# with encode_df (ENCODE's file table).
update_biosample_types <- function(files, biosample_types) {
  bio_colmap = c("biosample_type"="classification", "biosample_name"="term_name")
  files = pull_columns_append(files, biosample_types, "biosample_ontology", "id", bio_colmap)
  
  return(files)
}

# Fetches columns from ENCODE replicate table and merges them
# with encode_df (ENCODE's file table).
update_replicate <- function(files, replicates) {
  # Updating biological_replicate_list with replicates$biological_replicate_number
  replicate_col_map = c("biological_replicate_number",
                        "replicate_antibody"="antibody","technical_replicate_number")
  files = pull_columns_append(files, replicates, "replicate_list", "id", replicate_col_map)
  
  return(files)
}

# Fetches columns from ENCODE antibody_lot and antibody_characterization tables
# and merge them with encode_df (ENCODE's file table).
update_antibody <- function(files, antibody_lot, antibody_charac) {
  # Creating antibody target
  antibody_col_map = c("antibody_target"="targets", "antibody_characterization"="characterizations")
  files = pull_columns_append(files, antibody_lot, "replicate_antibody", "id", antibody_col_map)
  
  files$antibody_caption = pull_column(files, antibody_charac, "antibody_characterization", "id", "caption")
  files$antibody_characterization = pull_column_merge(files, antibody_charac, "antibody_characterization", "id", "characterization_method", "antibody_characterization")

  files$replicate_antibody <- remove_id_prefix(files$replicate_antibody)
  files$antibody_target <- remove_id_prefix(files$antibody_target)  
  
  return(files)  
}

# Fetches columns from ENCODE treatment table and merge them with 
# encode_df (ENCODE's file table).
update_treatment <- function(files, treatments, libraries, biosamples, replicates, datasets) {
  # Infer the biosample id from replicate -> library -> biosample chain.
  files$biosample_id = pull_column(files, libraries, "replicate_libraries", "id", "biosample")
  
  # Sometimes the replicate id is unavailable. The biosample can still sometime be inferred
  # through the dataset -> replicate -> library -> biosample chain.
  replicate_lists = pull_column(files, datasets, "accession", "accession", "replicates")
  
  # A dataset has multiple replicates, and we don't know which one maps to our file.
  # But all replicates should come from the same biosample, so we'll pick the first one
  # on the list.
  first_replicates = unlist(lapply(strsplit(replicate_lists, ";"), function(x) {trimws(x[1])}))
  
  # From the first replicate, we derive the biosample id.
  library_ids = pull_column_id(first_replicates, replicates, "id", "library")
  biosample_ids = pull_column_id(library_ids, libraries, "id", "biosample")
  
  # Now merge those biosample ids with those already known.
  files$biosample_id = ifelse(is.na(files$biosample_id), biosample_ids, files$biosample_id)
  
  # Now that we have the biosample, we might as well grab the organism.
  files$organism = pull_column(files, biosamples, "biosample_id", "id", "organism")
  
  # From the biosample id, infer the treatment id.
  files$treatment_id = pull_column(files, biosamples, "biosample_id", "id", "treatments")
  
  # Infer term from id when available. Replace id with term.
  files$treatment = files$treatment_id
  files$treatment = pull_column_merge(files, treatments, "treatment_id", "id", "treatment_term_name", "treatment")
  

  
  treatment_col_map = c("treatment_amount"="amount", "treatment_amount_unit"="amount_units", 
                        "treatment_duration"="duration", "treatment_duration_unit"="duration_units",
                        "treatment_temperature"="temperature", "treatment_temperature_unit"="temperature_units",
                        "treatment_notes"="notes")
  files = pull_columns_append(files, treatments, "treatment_id", "id", treatment_col_map)

  return(files)
}

# Fetches columns from ENCODE target and organism tables and merge them with 
# encode_df (ENCODE's file table).
update_target <- function(files, targets, organisms) {
  files$organism <- pull_column_merge(files, targets, "target", "id", "organism", "organism")
  
  files$investigated_as = pull_column(files, targets, "target", "id", "investigated_as")                 
  files$target = pull_column_merge(files, targets, "target", "id", "label", "target")

  files$organism <- pull_column_merge(files, organisms, "organism", "id", "scientific_name", "organism")  
  
  return(files)
}

# Split the dataset column into its type and accession components.
split_dataset_column <- function(files){
  # Step 5 : Splitting dataset column into two column
  dataset_types <- gsub(x = files$dataset, pattern = "/(.*)/.*/", 
                        replacement = "\\1")
  dataset_accessions <- gsub(x = files$dataset, pattern = "/.*/(.*)/", 
                             replacement = "\\1")
  
  files <- cbind(accession = dataset_accessions, dataset_type = dataset_types, 
                 files)
  
  return(files)
}

# Converts file sizes from raw numbers to human readable format.
file_size_conversion <- function(encode_exp) {
    # Converting the file size from byte to the Kb, Mb or Gb
    encode_exp$file_size <- sapply(encode_exp$file_size, function(size){
        
        if(!(is.na(size))){
            if(size < 1024){
                paste(size,"b") 
            }else if ((size >= 1024) & (size < 1048576)){
                paste(round(size/1024,digits = 1), "Kb")
            }else if ((size >= 1048576) & (size < 1073741824)){
                paste(round(size/(1048576),digits = 1), "Mb")
            }else{
                paste(round(size/1073741824, digits = 2), "Gb")
            }
        }
    })
    encode_exp$file_size = as.character(encode_exp$file_size)
    encode_exp
}