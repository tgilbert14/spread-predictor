# Rebuild the database from the snapshot files, then fit the two house
# models (Elo with its power-conference correction, and our Power rating),
# validate them season by season, score the holdout season, choose blend
# weights, write data/params.json and print the model gate report.
#
# Run from the project root:
#   Rscript scripts/fit.R
#   Rscript scripts/fit.R --db path/to/cfb.sqlite --out path/to/params.json

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

#' The value after a command-line flag, or a default when it is absent.
arg_value <- function(args, flag, default) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) default else args[[at + 1]]
}

args <- commandArgs(trailingOnly = TRUE)
db_path <- arg_value(args, "--db", PATHS$database)
out_path <- arg_value(args, "--out", PATHS$params)

# The database is cheap to rebuild, so do it every time. That way the fit
# always sees the snapshot files as they are now. Skipped when --db points at
# some other database.
if (identical(db_path, PATHS$database)) build_db()

con <- connect_readonly(db_path)
params <- tryCatch(fit_params(con), finally = DBI::dbDisconnect(con))
write_params(params, out_path)

cat(gate_report(params), sep = "\n")
cat(sprintf("\nWrote %s\n", out_path))
