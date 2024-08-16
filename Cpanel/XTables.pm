package Cpanel::XTables;

# cpanel - Cpanel/XTables.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $TIMEOUT = 20;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Cpanel::OS         ();
use Cpanel::IP::Parse  ();

# NOTE - This module is both a base class and a factory.

=head1 NAME

Cpanel::XTables

=head1 SYNOPSIS

    use Cpanel::XTables();

    my $obj = Cpanel::XTables->new( 'chain' => 'someChain' );
    my $rules = $obj->get_all_rules();

=head1 DESCRIPTION

This modules is both a *factory* and a *base class* for abstracting away
the differences between IPTables and NFTables so that interfaces which
rely on IP/NFTables don't have to maintain separate logic for these things.

Whichever subclass is the appropriate one to load for your OS Version will
be the object returned by the constructor:
CentOS 7 or below: Cpanel::IPTables object
CentOS 8: Cpanel::NFTables object

=head2 SEE ALSO

Cpanel::IpTables
Cpanel::NFTables
Cpanel::XTables::TempBan
Cpanel::XTables::Whitelist

=head1 METHODS

=head2 new

Provides the necessary object.

Parameters:
chain       - Required. The name of the chain
Returns:
A Cpanel::XTables object

=cut

sub new ( $class, %OPTS ) {

    my $chain = $OPTS{'chain'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'chain' ] ) if !$chain;

    my $implementor = Cpanel::OS::firewall_module();
    $class =~ s/XTables/$implementor/;

    my $self;
    {
        Cpanel::LoadModule::load_perl_module($class);
        $self = bless { 'chain' => $chain }, $class;
    }
    $self->_init(%OPTS);

    return $self;
}

=head2 clear_ruleset_cache

Implemented in subclasses. Noop here.

=cut

sub clear_ruleset_cache {
    return 1;
}

sub _init {
    die "_init only implemented in subclasses!";
}

=head2 purge_chain

Removes all rules and references to the chain from iptables/nftables

=cut

sub purge_chain ($self) {
    return 1 if !$self->chain_exists;
    $self->_remove_chain_from_all_builtin_chains();
    $self->clear_ruleset_cache();

    return 1;
}

sub _remove_chain_from_all_builtin_chains {
    die "_remove_chain_from_all_builtin_chains only implemented in subclasses!";
}

=head2 init_chain

Create the chain in iptables.
Any previous rules and references to this chain will be purged.
The chain will be reset to a "fresh" state.

=cut

sub init_chain ($self) {
    $self->purge_chain() if $self->chain_exists();
    $self->_create_chain();
    $self->clear_ruleset_cache();

    return 1;
}

sub _create_chain {
    die "_create_chain only implemented in Subclasses!";
}

=head2 attach_chain

Create the chain in iptables.
Attach the chain to another chain which would normally be considered
a "built-in target" within iptables.
Valid targets are: INPUT, OUTPUT, FORWARD

=cut

sub attach_chain ( $self, $target ) {
    die "The target chain to attach to must be one of the following: “INPUT, OUTPUT, FORWARD”." if $target !~ m{^(?:INPUT|OUTPUT|FORWARD)$};
    die "init_chain must be called before attach_chain: $self->{'chain'} does not exist!"       if !$self->chain_exists();
    $self->_attach_chain($target);
    $self->clear_ruleset_cache();

    return 1;
}

sub _attach_chain {
    die "Only implemented in subclasses!";
}

=head2 is_chain_attached

Returns true or false regarding whether a chain is attached to a given chain

=cut

sub is_chain_attached ( $self, $builtin_chain ) {
    my $attached_chains = $self->get_builtin_chains_that_reference_chain();

    return $attached_chains->{$builtin_chain} ? 1 : 0;
}

=head2 get_builtin_chains_that_reference_chain

Implemented in subclasses.

=cut

sub get_builtin_chains_that_reference_chain {
    die "get_builtin_chains_that_reference_chain only implemented in subclasses!";
}

=head2 validate_ip_is_correct_version_or_die

Ensures that the IP address's IP version matches the object's IP version

=cut

sub validate_ip_is_correct_version_or_die ( $self, $ipaddress ) {
    my ( $ipversion, $ipdata ) = Cpanel::IP::Parse::parse($ipaddress);

    if ( $self->{'ipversion'} && $ipversion != $self->{'ipversion'} ) {
        die "The IP version of the IP address must match the IP version of this object.";
    }
    return $ipdata;
}

=head2 chain_exists

Check to see if the object's chain exists

=cut

sub chain_exists ( $self, $chain = undef ) {
    $chain //= $self->{'chain'};
    my $rules_ref = $self->get_chain_rules($chain);
    return 1 if $self->_chain_rules_include_chain( $rules_ref, $chain );

    return 0;
}

sub _chain_rules_include_chain {
    die "Only implemented in subclasses!";
}

=head2 get_all_rules

Returns a list of all installed iptables/nftables rules (ARRAYREF).
See submodules for differences in data formats.
Probably should only be used in subclasses due to potentially different
outputs depending on your OS version.

=cut

sub get_all_rules ($self) {
    return $self->get_rules();
}

=head2 get_chain_rules

Returns a list of iptables rules for the object's chain as
an arrayref of arrayrefs. Same caveats for get_all_rules exists here.

=cut

sub get_chain_rules ( $self, $chain = undef ) {
    return $self->get_rules( $chain || $self->{'chain'} );
}

###########################################################################
#
# Method:
#   get_rules
#
# Description:
#   Returns ARRAYREF of the current rules defined. Must be setup in the subclass.
#
sub get_rules {
    die "get_rules only implemented in subclasses!";
}

=head2 supported_ip_versions

What versions are supported. Currently a list of ( 4, 6 ).

=cut

sub supported_ip_versions {
    return ( 4, 6 );
}

=head2 ipversion

Getter/setter for the ipversion of the object. Highly reccomended you use this
before doing things which require an ipversion set (like adding rules).

=cut

sub ipversion ( $self, $ver = undef ) {
    $self->{'ipversion'} = $ver if defined($ver);
    return $self->{'ipversion'} // 4;
}

=head2 exec_checked_calls

Only implemented in subclasses. Probably shouldn't be used outside of subclass.

=cut

sub exec_checked_calls {
    die "exec_checked_calls only implemented in subclasses!";
}

=head2 clear_firewall

Only implemented in subclasses. Probably shouldn't be used outside of subclass.

=cut

sub clear_firewall ($self) {
    return die "unimplemented";
}

1;
