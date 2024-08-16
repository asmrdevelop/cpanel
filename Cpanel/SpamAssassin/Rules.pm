package Cpanel::SpamAssassin::Rules;

# cpanel - Cpanel/SpamAssassin/Rules.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SpamAssassin::Rules - Tools for Apache SpamAssassin rule updates

=head1 SYNOPSIS

    use Cpanel::SpamAssassin::Rules ();


=head1 DESCRIPTION

Tools for Apache SpamAssassin rule updates

=cut

use Cpanel::SafeFind ();

our @sa_update_rule_paths;
eval {
    require Mail::SpamAssassin;

    my ($perl_version) = ( $] =~ /^(\d\.\d\d\d)/a );

    @sa_update_rule_paths = grep { -d $_ } (
        "/var/lib/spamassassin/$perl_version/$Mail::SpamAssassin::VERSION",
        "/var/lib/spamassassin/$Mail::SpamAssassin::VERSION"
    );

};

our @all_rule_paths = (
    @sa_update_rule_paths,
    grep { -d $_ } (
        '/usr/share/spamassassin',
        '/etc/mail/spamassassin',
        '/usr/local/cpanel/etc/mail/spamassassin',
    ),
);

=head2 has_rules_installed()

Returns 1 if there are rules installed, returns
0 if there are no rules installed

=cut

sub has_rules_installed {
    return _get_mtime_of_sa_update_rules() ? 1 : 0;
}

=head2 get_mtime_of_newest_rule()

Returns the mtime of the newest installed ruleset or 0 if
there are no installed rules

=cut

sub get_mtime_of_newest_rule {
    return _get_mtime_of_newest_rule_in_paths(@all_rule_paths);
}

sub _get_mtime_of_sa_update_rules {
    return _get_mtime_of_newest_rule_in_paths(@sa_update_rule_paths);
}

sub _get_mtime_of_newest_rule_in_paths {
    my (@possible_rule_paths) = @_;
    my $sa_rule_mtime = 0;
    Cpanel::SafeFind::finddepth(    # Must use finddepth since find is not available here
        sub {
            return if $File::Find::name !~ m{\.(?:pre|cf)$};
            my $mtime = ( lstat($File::Find::name) )[9];
            return                  if !$mtime || !-f _;
            $sa_rule_mtime = $mtime if $sa_rule_mtime < $mtime;
        },
        @possible_rule_paths
    );

    return $sa_rule_mtime;
}

1;
