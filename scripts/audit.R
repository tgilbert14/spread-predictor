# Audit cfb.sqlite: run every data check, print a report, and write
# docs/data-audit.md for people who will not read the console.
#
# Run from the project root:
#   Rscript scripts/audit.R
#   Rscript scripts/audit.R --db path/to/cfb.sqlite --out path/to/report.md
#
# Exits with status 1 if any "error" check finds rows, so it can gate a
# refresh or a CI job. Never changes the database.

for (file in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(file)

#' The value after a command-line flag, or a default when it is absent.
flag_value <- function(args, flag, default) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) default else args[[at + 1]]
}

args <- commandArgs(trailingOnly = TRUE)
db_path <- flag_value(args, "--db", PATHS$database)
out_path <- flag_value(args, "--out", file.path("docs", "data-audit.md"))

if (!file.exists(db_path)) {
  stop("No database at ", db_path, ". Build it with Rscript scripts/refresh.R --offline, then try again.",
       call. = FALSE)
}

# Read-only, so the audit can never change what it is checking.
con <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
audit <- tryCatch(
  list(summary = audit_db(con), counts = audit_table_counts(con)),
  finally = DBI::dbDisconnect(con)
)
summary <- audit$summary
counts <- audit$counts

audit_print(summary, counts)
writeLines(audit_markdown(summary, counts), out_path, useBytes = TRUE)
cat("\nWrote ", out_path, ".\n", sep = "")

if (audit_has_errors(summary)) {
  cat("At least one check that could corrupt the model found problems. See the report.\n")
  quit(status = 1)
}
cat("No check that could corrupt the model found problems.\n")
