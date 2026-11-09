# Load every function in R/ before the tests run.
# Tests run from tests/testthat/, so the project root is two levels up.
project_root <- normalizePath(file.path("..", ".."))
for (file in list.files(file.path(project_root, "R"), pattern = "\\.R$", full.names = TRUE)) {
  source(file)
}
