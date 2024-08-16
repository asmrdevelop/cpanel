package Cpanel::LinkedNode::Convert::CrossDistributed::Mail::Backend;

# cpanel - Cpanel/LinkedNode/Convert/CrossDistributed/Mail/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::CrossDistributed::Mail::Backend

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This module implements some specific logic for distributed-mail
cross-conversion.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

use Cpanel::Imports;

use Cpanel::LinkedNode::Convert::Common::Mail::FromRemote ();
use Cpanel::PromiseUtils                                  ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 step__set_up_source_manual_mx ( \%INPUT, $STATE_OBJ )

Points manual MX on the source node to the target node.

=cut

sub step__set_up_source_manual_mx ( $input_hr, $state_obj ) {
    Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::set_up_source_manual_mx(
        $input_hr,
        $state_obj,
        $state_obj->get('target_node_obj')->hostname(),
    );

    return;
}

=head2 step__set_up_source_service_proxy ( \%INPUT, $STATE_OBJ )

Points service proxies on the source node to the target node.

=cut

sub step__set_up_source_service_proxy ( $input_hr, $state_obj ) {
    Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::set_up_source_service_proxy(
        $input_hr,
        $state_obj,
        $state_obj->get('target_node_obj')->hostname(),
    );

    return;
}

=head2 step__make_target_node_download_mail( \%INPUT, $STATE_OBJ )

Makes the target node download mail.

=cut

sub step__make_target_node_download_mail ( $input_hr, $state_obj ) {
    my $source_node_obj = $state_obj->get('source_node_obj');
    my $target_node_obj = $state_obj->get('target_node_obj');

    my $cstream = $target_node_obj->get_commandstream();

    my $output_obj = $input_hr->{'output_obj'};

    my @indents;

    my $p = $cstream->request(
        'mailsync',
        hostname  => $source_node_obj->hostname(),
        api_token => $source_node_obj->api_token(),
        username  => $input_hr->{'username'},
    )->then(
        sub ($request) {
            return $request->started_promise();
        },
    )->then(
        sub ($user_fate_hr) {
            my $count = 0 + keys %$user_fate_hr;

            $output_obj->out( locale()->maketext( 'Copying [quant,_1,email account’s,email accounts’] mail …', $count ) );

            push @indents, $output_obj->create_indent_guard();

            my @handlers;

            for my $name ( keys %$user_fate_hr ) {
                push @handlers, $user_fate_hr->{$name}->then(
                    sub {
                        $output_obj->success("$name: OK");
                    },
                    sub ($why) {
                        return Promise::XS::rejected("$name: $why");
                    },
                );
            }

            return Promise::XS::all(@handlers)->then( sub { } );
        },
    );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

1;
