package Cpanel::Exim::Config::Def;

# cpanel - Cpanel/Exim/Config/Def.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our @OFF_DEFAULT_FILTERS = qw(
  fail_spam_score_over_100
  fail_spam_score_over_125
  fail_spam_score_over_150
  fail_spam_score_over_175
  fail_spam_score_over_200
  fail_spam_score_over_int
);

our @OFF_DEFAULT_ACLS = qw(
  0tracksenders
  requirehelonold
  dkim_bl
  primary_hostname_bl
  spamhaus_rbl
  spamcop_rbl
  spamhaus_spamcop_rbl
  deny_spam_score_over_100
  deny_spam_score_over_125
  deny_spam_score_over_150
  deny_spam_score_over_175
  deny_spam_score_over_200
  deny_spam_score_over_int
  ratelimit_spam_score_over_100
  ratelimit_spam_score_over_125
  ratelimit_spam_score_over_150
  ratelimit_spam_score_over_175
  ratelimit_spam_score_over_200
  ratelimit_spam_score_over_int
  deny_rcpt_hard_limit
  deny_rcpt_soft_limit
  outgoing_spam_scan
  outgoing_spam_scan_over_int
  outgoing_malware_scan
  no_forward_outbound_spam
  no_forward_outbound_spam_over_int
);

our @CONFIGURED_OPTIONS = qw(
  daemon_smtp_ports
  spamd_address
  tls_on_connect_ports
  tls_require_ciphers
  system_filter_user
  system_filter_group
);
1;
