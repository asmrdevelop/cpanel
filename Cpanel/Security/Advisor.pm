package Cpanel::Security::Advisor;

# cpanel - Cpanel/Security/Advisor.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Security::Advisor - cPanel Security Advisor

=head1 SYNOPSYS

    my $comet = Cpanel::Comet::Mock->new();

    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Advisor');
    my $advisor = Cpanel::Security::Advisor->new( 'comet' => $comet, 'channel' => $CHANNEL );

    my ( $merged, @result ) = Capture::Tiny::capture_merged(
        sub {
            $advisor->generate_advice();
        }
    );

    my $msgs = $comet->get_messages($CHANNEL);
    foreach my $msg ( @{$msgs} ) {
        my $msg_ref = Cpanel::AdminBin::Serializer::Load($msg);

        ....

    }

=cut

use strict;
use warnings;

our $VERSION = 1.04;

use Cpanel::Config::LoadCpConf   ();
use Cpanel::Logger               ();
use Cpanel::JSON                 ();
use Cpanel::Locale               ();
use Cpanel::LoadModule           ();
use Cpanel::LoadModule::AllNames ();

use Try::Tiny;

our $ADVISE_GOOD = 1;
our $ADVISE_INFO = 2;
our $ADVISE_WARN = 4;
our $ADVISE_BAD  = 8;

# provides string type given integer value
sub _lookup_advise_type {
    my $int                 = shift;
    my $ADVISE_TYPES_LOOKUP = {
        $ADVISE_GOOD => q{ADVISE_GOOD},
        $ADVISE_INFO => q{ADVISE_INFO},
        $ADVISE_WARN => q{ADVISE_WARN},
        $ADVISE_BAD  => q{ADVISE_BAD},
    };
    return ( $int and $ADVISE_TYPES_LOOKUP->{$int} ) ? $ADVISE_TYPES_LOOKUP->{$int} : undef;
}

# provides integer value given type string
sub _lookup_advise_type_by_value {
    my $type                 = shift;
    my $ADVISE_VALUES_LOOKUP = {
        q{ADVISE_GOOD} => $ADVISE_GOOD,
        q{ADVISE_INFO} => $ADVISE_INFO,
        q{ADVISE_WARN} => $ADVISE_WARN,
        q{ADVISE_BAD}  => $ADVISE_BAD,
    };
    return ( $type and $ADVISE_VALUES_LOOKUP->{$type} ) ? $ADVISE_VALUES_LOOKUP->{$type} : undef;
}

=head1 ADVISE TYPES

=head2 ADVISE_GOOD

=over

Changes DO NOT send iContact notices

=back

All is well

=head2 ADVISE_INFO

=over

Changes send iContact notices for 11.56.0.14 and below, Changes DO NOT send iContact notices for 11.56.0.15 and above

=back

For items that may not be be actionable soon but should know about.
If there is uncertainty if the admin has control over the item or
if we have less than 90% confidence that its not a false positive.

=head2 ADVISE_WARN

=over

Changes send iContact notices

=back

For items that should be actioned soon.  These should be
95% confidence or better that it is not a false positive.

=head2 ADVISE_BAD

=over

Changes send iContact notices

=back

For items that should be actioned now.  These should be 99%
confidence or better that it is not a false positive.

=cut

sub new {
    my ( $class, %options ) = @_;

    die "No comet object provided"  unless ( $options{'comet'} );
    die "No comet channel provided" unless ( $options{'channel'} );

    my @assessors;

    my $self = bless {
        'assessors' => \@assessors,
        'logger'    => Cpanel::Logger->new(),
        'cpconf'    => scalar Cpanel::Config::LoadCpConf::loadcpconf(),
        '_version'  => $VERSION,
        '_cache'    => {},
        'comet'     => $options{'comet'},
        'channel'   => $options{'channel'},
        'locale'    => Cpanel::Locale->get_handle(),
    }, $class;

    local @INC = ( @INC, '/var/cpanel/addons/securityadvisor/perl' );
    my @modules = sort keys %{ Cpanel::LoadModule::AllNames::get_loadable_modules_in_namespace('Cpanel::Security::Advisor::Assessors') };
    foreach my $module_name (@modules) {
        my $object;
        try {
            Cpanel::LoadModule::load_perl_module($module_name);
            $object = $module_name->new($self);
        }
        catch {
            $self->{'logger'}->warn("Failed to load $module_name: $_");
            $self->_internal_message( { type => 'mod_load', state => 0, module => $module_name, message => "$_" } );
        };
        next unless $object;

        push @assessors, { name => $module_name, object => $object };
        my $runtime = ( $object->can('estimated_runtime') ? $object->estimated_runtime() : 1 );
        $self->_internal_message( { type => 'mod_load', state => 1, module => $module_name, runtime => $runtime } );
    }

    return $self;
}

sub generate_advice {
    my ($self) = @_;

    $self->_internal_message( { type => 'scan_run', state => 0 } );
    foreach my $mod ( sort { lc $a->{'name'} cmp lc $b->{'name'} } @{ $self->{'assessors'} } ) {
        my $module         = $mod->{'name'};
        my $version_ref    = "$module"->can('version');
        my $module_version = $version_ref ? $version_ref->() : '';

        $self->_internal_message( { type => 'mod_run', state => 0, module => $mod->{name}, 'version' => $module_version } );
        eval { $mod->{object}->generate_advice(); };
        $self->_internal_message( { type => 'mod_run', state => ( $@ ? -1 : 1 ), module => $mod->{name}, message => "$@", 'version' => $module_version } );
    }
    $self->_internal_message( { type => 'scan_run', state => 1 } );
    $self->{'comet'}->purgeclient();
    return;
}

sub _internal_message {
    my ( $self, $data ) = @_;
    $self->{'comet'}->add_message(
        $self->{'channel'},
        Cpanel::JSON::Dump(
            {
                channel => $self->{'channel'},
                data    => $data
            }
        ),
    );
    return;
}

sub add_advice {
    my ( $self, $advice ) = @_;

    # Some assessor modules call methods directly on instances of this class,
    # and some use wrapper methods, so try to figure out the module name
    # regardless of which path we took.
    my ( $module, $function );
    foreach my $level ( 1, 3 ) {
        my $caller = ( caller($level) )[3];
        if ( $caller =~ /(Cpanel::Security::Advisor::Assessors::.+)::([^:]+)$/ ) {
            ( $module, $function ) = ( $1, $2 );
            last;
        }
    }

    $self->{'comet'}->add_message(
        $self->{'channel'},
        Cpanel::JSON::Dump(
            {
                channel => $self->{'channel'},
                data    => {
                    type     => 'mod_advice',
                    module   => $module,
                    function => $function,
                    advice   => $advice,
                }
            }
        ),
    );
    return;
}

1;
