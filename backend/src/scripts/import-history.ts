process.stderr.write(
  "The upstream history format has not been verified; import is disabled to prevent fabricated records.\n",
);
process.exitCode = 1;
