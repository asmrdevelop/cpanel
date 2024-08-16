package Cpanel::NFTables;

# cpanel - Cpanel/NFTables.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::XTables';

use Cpanel::Binaries        ();
use Cpanel::JSON            ();
use Cpanel::SafeRun::Errors ();
use Cpanel::SafeRun::Object ();

use Cpanel::OS ();

use constant {
    IP_FAMILY => 'inet',
    TABLE     => 'filter',
};

=head1 NAME

Cpanel::NFTables

=head1 SYNOPSIS

    use Cpanel::NFTables;

    my $rules_ar     = Cpanel::NFTables::new()->get_rules;
    my $rule_added   = Cpanel::NFTables::add_rule(
        'chain'    => 'gold',
        'ip'       => '1.2.3.4',
        'port'     => 1234,
        'protocol' => 'tcp',
        'action'   => 'DROP',
    );
    my $rule_deleted = Cpanel::NFTables::delete_rule(
        'handle' => 4321,
        'chain'  => 'gold'
    );

=head1 DESCRIPTION

This module is intended to provide wrappers around the 'nft' binary in much
the same way as 'Cpanel::IpTables' does. See Cpanel::XTables for the abstraction
layer used for these two namespaces.

More functionality will be coming soon, as it is required in many places for
proper CentOS 8 support.

Soon:
* Abstraction around whether to use IpTables or NFTables (for cPHulk)
* Configuration persistence routines

=head1 SUBROUTINES

=cut

sub _init ( $self, @ ) {
    $self->{'binary'} = Cpanel::Binaries::path('nft');
    return $self;
}

sub exec_checked_calls ( $self, $calls ) {
    my @results;
    foreach my $call (@$calls) {
        my $output;
        my @args = ( ref $call eq 'ARRAY' ? @$call : $call );

        #print STDERR "# nft @args\n";
        $output = Cpanel::SafeRun::Errors::saferunallerrors( $self->{'binary'}, @args );
        my $child_status = $SIG{'CHLD'} && $SIG{'CHLD'} eq 'IGNORE' ? 0 : $?;
        if ( $child_status != 0 ) {
            require Cpanel::ChildErrorStringifier;
            my $autopsy = $child_status == -1 ? 'Failed to execute' : Cpanel::ChildErrorStringifier->new($child_status)->autopsy();
            $output //= "";
            die "[nftables] “$self->{'binary'} @args” failed: $output: $autopsy";
        }

        push @results, $output;
    }
    return \@results;
}

sub _create_table ( $self, $class, $table ) {
    $self->exec_checked_calls(
        [ [ qw{add table}, $class, $table ] ],
    );
    return 1;
}

sub _create_chain ($self) {

    $self->_create_table( IP_FAMILY, TABLE );
    $self->exec_checked_calls(
        [ [ qw{add chain}, IP_FAMILY, TABLE, $self->{'chain'} ] ],
    );
    return 1;
}

sub _remove_chain_from_all_builtin_chains ($self) {
    my @calls;
    my %families;

    # OK, now remove all linked chains since we flush above
    my $rules = $self->_get_reference_rules_within_builtin_chains();
    foreach my $rule (@$rules) {
        push @calls, [ qw{delete rule}, $rule->{'family'}, $rule->{'table'}, $rule->{'chain'}, 'handle', $rule->{'handle'} ];
        $families{ $rule->{'family'} . '_' . $rule->{'table'} } = {
            'family' => $rule->{'family'},
            'table'  => $rule->{'table'},
        };
    }

    # For each family/table type we've encountered, flush & delete the chain
    foreach my $value ( values %families ) {
        unshift @calls, [ qw{flush chain}, $value->{'family'}, $value->{'table'}, $self->{'chain'} ];
        push @calls, [ qw{delete chain}, $value->{'family'}, $value->{'table'}, $self->{'chain'} ];
    }

    $self->exec_checked_calls( \@calls );

    return 1;
}

sub _chain_rules_include_chain ( $self, $rref, $chain = undef ) {
    $chain //= $self->{'chain'};
    my @matches = grep {
        my $o = $_;
        $o->{'name'} eq $chain
    } @{ $self->chains() };

    return @matches;
}

sub _attach_chain ( $self, $target ) {
    my @priority = qw/{ type filter hook input priority 0 ; }/;
    my @calls    = (
        [ qw{ add chain }, IP_FAMILY, TABLE, $target, @priority ],
        [ qw{ add rule  }, IP_FAMILY, TABLE, $target, qw{counter jump}, $self->{'chain'} ]
    );

    $self->exec_checked_calls( \@calls );

    return 1;
}

sub get_builtin_chains_that_reference_chain ($self) {
    my %chains;
    foreach my $rule ( $self->get_rules->@* ) {
        my ($jump) = grep { my $j = $_; $j->{'jump'} && $j->{'jump'}{'target'} } @{ $rule->{'expr'} };
        $chains{ $rule->{'chain'} } = $jump->{'jump'}{'target'} if $jump;
    }

    # chain => referenced chain
    return \%chains;
}

sub _get_reference_rules_within_builtin_chains ($self) {
    my @matches;
    foreach my $rule ( $self->get_rules->@* ) {
        my ($jump) = grep { my $j = $_; $j->{'jump'} && $j->{'jump'}{'target'} && $j->{'jump'}{'target'} eq $self->{'chain'} } @{ $rule->{'expr'} };
        push @matches, $rule if $jump;
    }

    # chain => referenced chain
    return \@matches;
}

=head2 meta

Returns HASHREF of various metadata about NFTables including version data.

=cut

sub meta ($self) {
    return $self->_items('meta');
}

=head2 tables

Returns ARRAYREF of the current tables defined.

=cut

sub tables ($self) {
    return $self->_items('tables');
}

=head2 chains

Returns ARRAYREF of the current chains defined.

=cut

sub chains ($self) {
    return $self->_items('chains');
}

=head2 rules

Returns ARRAYREF of the current rules defined.

=cut

sub get_rules ( $self, @ ) {
    return $self->_items('rules');
}

sub sets ($self) {
    return $self->_items('sets');
}

sub _items ( $self, $item ) {
    return $self->{$item} if $self->{$item};
    $self->_load_nft_data();
    return $self->{$item};
}

sub _load_nft_data ($self) {
    my @cc_args = qw{--json list ruleset};
    my $nft_sro = Cpanel::SafeRun::Object->new(
        'program' => $self->{'binary'},
        'args'    => \@cc_args,
    );
    if ( !$nft_sro->to_exception() ) {
        my $json_rules = $nft_sro->stdout();
        my $decoded    = { 'nftables' => [] };
        $decoded = Cpanel::JSON::Load($json_rules) if length $json_rules;
        $self->_transform_ruleset($decoded);
    }
    else {
        my $output  = $nft_sro->stderr();
        my $autopsy = $nft_sro->autopsy();
        die "[nftables] “$self->{'binary'} @cc_args” failed: $output: $autopsy";
    }

    return;
}

# Still possibly called by whostmgr/docroot/cgi/hostaccess.cgi as other firewall backends still use caching and this
# function needs to exist in all the firewall handling modules
sub clear_ruleset_cache ($self) {
    foreach my $item (qw{sets rules chains meta}) {
        undef $self->{$item};
    }
    return;
}

sub _transform_ruleset ( $self, $blob ) {
    $self->{'meta'} = shift @{ $blob->{'nftables'} };
    $self->{$_} = [] for qw{tables chains rules sets};
    foreach my $entry ( @{ $blob->{'nftables'} } ) {

        # There's only one key. JSON schema is somewhat
        # overwrought.
        my $entry_type = ( keys(%$entry) )[0];
        push @{ $self->{"${entry_type}s"} }, $entry->{$entry_type};
    }
    return;
}

=head2 add_rule

Allows adding a specific sort of rule. Not quite as powerful as Cpanel::IpTables'
'exec_checked_calls', but this was due to it being made for a specific use case.

This is a fairly primitive implementation, mostly aimed at allowing
Some semblance of Host Access Control.

Accepted arguments (HASH):
* chain:    What chain to add the rule to. Will fail if it doesn't exist.
* ip:       What IP to manage. use 'ALL' if you don't care about the source IP.
* port:     What port to manage.
* protocol: What protocol to manage. Valid types are 'tcp' and 'udp'.
* action:   What to do with the rule.
Valid types are 'DROP', 'ACCEPT' and 'REJECT'.

Returns 1 on success, dies on failure or bad arguments.

=cut

sub add_rule ( $self, %opts ) {

    # Need exception here
    die "Bad Args" if grep { !$opts{$_} } qw{ip port protocol action};
    $self->_create_chain;

    my @rules = ( [ qw{add chain }, IP_FAMILY, TABLE, $self->{'chain'} ] );

    # Add ct state new just in case you mistakenly specify ALL for ports or something then realize your mistake while SSH'd in
    my $rule = [ qw{add rule }, IP_FAMILY, TABLE, $self->{'chain'} ];
    if ( $opts{'ip'} && lc( $opts{'ip'} ) ne 'all' ) {
        require Cpanel::IP::Parse;
        my ( $ipversion, $ipdata ) = Cpanel::IP::Parse::parse( $opts{'ip'} );
        my $ver_str = $ipversion == 6 ? $ipversion : "";
        push @$rule, "ip$ver_str", 'saddr', $opts{'ip'};
    }
    push @$rule, qw{ct state new}, $opts{'protocol'}, 'dport', $opts{'port'}, 'counter', $opts{'action'};
    push @rules, $rule;
    $self->exec_checked_calls( \@rules );
    $self->save_current_ruleset();
    return 1;
}

=head2 delete_rule

Allows deleting an NFTables rule.

Accepted arguments (HASH):
* chain:  What chain to add the rule to. Will fail if it doesn't exist.
* handle: ID number of the rule.

Returns 1 on success, dies on failure or bad arguments.

=cut

sub delete_rule ( $self, %opts ) {
    die "Bad Args" if grep { !$opts{$_} } qw{handle};
    my $args = [ qw{delete rule }, IP_FAMILY, TABLE, $self->{'chain'}, 'handle', $opts{'handle'} ];
    $self->exec_checked_calls( [$args] );
    $self->save_current_ruleset();
    return 1;
}

sub save_current_ruleset ($self) {
    my $cfg = Cpanel::OS::nftables_config_file();

    my $out = Cpanel::SafeRun::Errors::saferunallerrors( $self->{'binary'}, qw{list ruleset} );
    if ($out) {
        chomp($out);
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::overwrite( $cfg, $out );
    }
    return;
}

sub set_exists ( $self, $set ) {
    return grep {
        my $sn = $_->{'set'}{'name'};
        $sn && $sn eq $set;
    } @{ $self->sets() };
}

=head2 table_exists

Check to see if the table which you specify exists.
Since all the relevant tables always exist on iptables, this wasn't added to
the parent module.

Args:
  family => Family of the filter -- ex. "inet" or "ip"
  name   => Name of the table -- ex. "filter" or "nat"

=cut

sub table_exists ( $self, %opts ) {
    die "Bad args! Needed: 'name', 'family'" if ( !$opts{name} || !$opts{family} );
    my $tables = $self->tables() // [];
    return unless scalar @$tables;
    return grep { $_->{name} eq $opts{name} && $_->{family} eq $opts{family} } @$tables;
}

sub clear_firewall ($self) {
    return $self->exec_checked_calls( [ [qw/flush ruleset/] ] );
}

1;
