package Cpanel::LinkedNode::Convert::Common::FromRemote;

# cpanel - Cpanel/LinkedNode/Convert/Common/FromRemote.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::FromRemote

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This module holds logic common for any from-remote conversion,
regardless of workload.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Config::LoadCpUserFile           ();
use Cpanel::LinkedNode::Index::Read          ();
use Cpanel::LinkedNode::Worker::Storage      ();
use Cpanel::LinkedNode::Worker::WHM::Pkgacct ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 step__pkgacct_on_source( \%INPUT, $STATE_OBJ )

Backs up the existing child-node account and waits until that
backup is complete.

This omits most of the “expensive” stuff, so it shouldn’t take long.

=cut

sub step__pkgacct_on_source ( $input_hr, $state_obj ) {
    my $work_dir = Cpanel::LinkedNode::Worker::WHM::Pkgacct::execute_pkgacct_for_user(
        $state_obj->get('source_node_obj')->alias(),
        $input_hr->{'username'},
    );

    $state_obj->set(
        source_backup_dir => $work_dir,
    );

    $input_hr->{'output_obj'}->out(
        locale()->maketext('Archive path:') . " $work_dir",
    );

    return;
}

#----------------------------------------------------------------------

=head2 $node_obj = get_source_node_obj( $USERNAME, $WORKLOAD )

Returns a L<Cpanel::LinkedNode::Privileged::Configuration> instance for
the given $USERNAME and $WORKLOAD.

=cut

sub get_source_node_obj ( $username, $workload ) {
    my $cpuser_hr   = Cpanel::Config::LoadCpUserFile::load_or_die($username);
    my $node_ar     = Cpanel::LinkedNode::Worker::Storage::read( $cpuser_hr, $workload );
    my $child_alias = $node_ar->[0];

    die "Account “$username” uses the local server for “$workload” functionality" if !length $child_alias;

    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    return $nodes_hr->{$child_alias} || do {
        die "No child node with alias “$child_alias” exists.";
    };
}

1;
