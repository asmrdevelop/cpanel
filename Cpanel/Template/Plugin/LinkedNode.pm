package Cpanel::Template::Plugin::LinkedNode;

# cpanel - Cpanel/Template/Plugin/LinkedNode.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LinkedNode::Alias::Constants ();    # PPI USE OK - Constants

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::LinkedNode

=head1 DESCRIPTION

A TT plugin that exposes linked-node logic for cPanel.

(NB: If any APIs materialize that expose this information, then prefer
those.)

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Worker::GetAll ();

#----------------------------------------------------------------------

use parent 'Template::Plugin';

=head1 METHODS

=head2 new

Constructor

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

A new C<Cpanel::Template::Plugin::LinkedNode> object

=back

=back

=cut

sub new {
    return bless {}, $_[0];
}

sub _get_cpdata {
    return \%Cpanel::CPDATA;
}

=head2 get_basic_worker_data()

This calls
C<Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser()>
for the current cPanel user and returns the result in an array (reference).

=cut

sub get_basic_worker_data ($self) {
    die 'Need %Cpanel::CPDATA!' if !_get_cpdata();

    return [ Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser( _get_cpdata() ) ];
}

=head2 has_linkages

Determines if any linkages exist for this account

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

Boolean value 1|0 based on the existence of any server linkages.

=back

=back

=cut

sub has_linkages ($self) {

    if ( scalar @{ $self->get_basic_worker_data() } ) {
        return 1;
    }

    return 0;
}

=head2 get_child_node_options

Build an iterable list of worker types, values and options

=over 2

=item Input

=over 3

=item C<HASHREF>

$linked_nodes_hr - the values of the currently linked nodes on the server. This will be keyed
by the alias, and must include the hostname, and a hashref of worker capabilities. The results of
Cpanel::LinkedNode::Index::Read::get() is the expected format.

    {
        'septcinq' => {
            'hostname' => 'sept.example.com',
            'worker_capabilities' => {'Mail' => {}},
        },
        'six' => {
            'hostname' => 'six.example.com',
            'worker_capabilities' => {'Mail' => {}},
        }
    }

=back

=item C<ARRAYREF>

$user_child_nodes_ar - the values of specific users currently utilized child nodes. The results of
Cpanel::LinkedNode::Worker::GetAll::get_all_from_cpuser($cpuser_ref) contains the necessary data.

    [
        {
            'worker_type' => 'Mail',
            'alias' => 'six'
        }
    ]

=item Output

=over 3

=item C<HASHREF>

Returns a type keyed hashref for each of the currently supported worker types on the server.

    {
        'Mail' => {
            'label' => 'Mail',
            'parameter' => 'mail_node_alias',
            'options' => [
                {
                    'alias' => 'septcinq',
                    'hostname' => 'sept.example.com'
                },
                {
                    'alias' => 'six',
                    'hostname' => 'six.example.com'
                }
            ],
            'value' => '.local'
        }
    }

=back

=back

=cut

sub get_child_node_options {
    my ( $self, $linked_nodes_hr, $user_child_nodes_ar ) = @_;

    # Control keys for supported types
    my $local_child_node_value = Cpanel::LinkedNode::Alias::Constants::LOCAL;

    require Cpanel::Locale;
    my $locale      = Cpanel::Locale->get_handle();
    my $child_types = {
        'Mail' => {
            label     => $locale->maketext('Mail'),
            parameter => 'mail_node_alias',
        },
    };

    my $linked_nodes_by_type = {};
    my $child_nodes          = {};

    if ( !$linked_nodes_hr || !%$linked_nodes_hr ) {
        return;
    }

    # Process linked nodes
    foreach my $linked_node_alias ( sort keys %$linked_nodes_hr ) {
        my $linked_node = $linked_nodes_hr->{$linked_node_alias};

        # Don't send to store more information than we need to, including tokens
        my $minimal_linked_node = {
            alias    => $linked_node_alias,
            hostname => $linked_nodes_hr->{$linked_node_alias}->{'hostname'},
        };

        # For every type it is capable of being, add to that list
        my $worker_capabilities = $linked_node->{'worker_capabilities'};
        foreach my $child_type ( keys %$worker_capabilities ) {
            $linked_nodes_by_type->{$child_type} ||= [];
            push @{ $linked_nodes_by_type->{$child_type} }, $minimal_linked_node;
        }
    }

    # Setup defaults
    foreach my $child_type ( keys %$child_types ) {
        if ( !$linked_nodes_by_type->{$child_type} ) {

            # If there aren't any listed, we don't need to include this child type
            next;
        }
        $child_nodes->{$child_type} = {
            'label'     => $child_types->{$child_type}->{'label'},
            'parameter' => $child_types->{$child_type}->{'parameter'},
            'value'     => $local_child_node_value,
            'options'   => $linked_nodes_by_type->{$child_type},
        };
    }

    if ($user_child_nodes_ar) {
        foreach my $user_child_node ( @{$user_child_nodes_ar} ) {
            my $child_type = $user_child_node->{'worker_type'};

            $child_nodes->{$child_type}->{'value'}   = $user_child_node->{'alias'};
            $child_nodes->{$child_type}->{'whm_url'} = 'https://' . $linked_nodes_hr->{ $user_child_node->{'alias'} }->{'hostname'} . ":$ENV{'SERVER_PORT'}/";
        }
    }

    # Cleanup servers for resellers
    require Whostmgr::ACLS;
    if ( !Whostmgr::ACLS::hasroot() ) {
        foreach my $child_type ( keys %$child_nodes ) {
            if ( $child_nodes->{$child_type}->{'value'} eq $local_child_node_value ) {

                # Remove types that are set to local so they don't get displayed in the interface.
                delete $child_nodes->{$child_type};
                next;
            }
        }

        if ( !keys %$child_nodes ) {
            return;
        }
    }

    return keys %$child_nodes ? $child_nodes : undef;

}

1;
