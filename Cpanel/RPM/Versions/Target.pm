package Cpanel::RPM::Versions::Target;

# cpanel - Cpanel/RPM/Versions/Target.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::RPM::Verions::Target - Tools to easily enable/disable rpm.versions targets.

=head1 SYNOPSIS

    use Cpanel::RPM::Versions::Target ();

    Cpanel::RPM::Versions::Target::enable('mailman');
    Cpanel::RPM::Versions::Target::disable('mailman');

=head1 DESCRIPTION

Makes it easy to disable a target (in local.versions) and update rpms installed after this is complete.

=head1 SUBROUTINES

=cut

use cPstrict;

use Cpanel::RPM::Versions::File ();

=head2 restore_to_defaults

Remove a target (first arg) from local.versions, reverting back to whatever rpm.versions dictates. If the second argument (optional) is false, check_cpanel_pkgs is not run for that target.

=cut

sub restore_to_defaults ( $target, $check = 1 ) {
    my $versions = Cpanel::RPM::Versions::File->new;
    $versions->delete_target_settings( { 'key' => $target } );
    $versions->save();
    check_cpanel_pkgs($target) if $check;

    return;
}

=head2 set

Set the value of a target (first arg) to a value (second arg) in local.versions. If the third argument (optional) is false, check_cpanel_pkgs is not run for that target.

=cut

sub set ( $target, $value, $check = 1 ) {
    my $versions = Cpanel::RPM::Versions::File->new;

    $value =~ m/^(?:un)?installed|unmanaged$/ or die "Unrecoginzed value '$value' set for target '$target'. Supported values are: installed, uninstalled, unmanaged";

    my $error = $versions->set_target_settings( { 'key' => [$target], 'value' => $value } );
    warn $error if length $error;    # Maybe this should die but what then?
    $versions->save();
    check_cpanel_pkgs($target) if $check;

    return;
}

=head2 check_cpanel_pkgs

Easy helper to run check_cpanel_pkgs from code. NOTE: right now output is dumped to STDOUT.

=cut

sub check_cpanel_pkgs (@targets) {

    # We should be giving more options for output but for now this is good enough for the existing callers.

    my @args = qw(  --fix --long-list --no-broken --no-digest );
    push @args, '--targets', join( ",", @targets ) if @targets;

    require '/usr/local/cpanel/scripts/check_cpanel_pkgs';
    return scripts::check_cpanel_pkgs->script(@args);
}

1;
