package Cpanel::SecurityPolicy::Base;

# cpanel - Cpanel/SecurityPolicy/Base.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

use Cpanel::Logger;

# Duplicated from Cpanel::SecurityPolicy, not a good idea.
my $security_policy_dir = '/usr/local/cpanel';
my $user_sec_policy_dir = '/var/cpanel/perl';
my $secpol_ns           = 'Cpanel::Security::Policy';

my %UITYPES = (
    'xml'      => 'XMLAPI',
    'json'     => 'JsonApi',
    'dnsadmin' => 'Text',
    'html'     => 'HTML',
);

sub init {
    my ( $class, $pkg, $priority ) = @_;

    die "'$pkg' is not a valid namespace name.\n" unless $pkg        =~ /^\w+(?:::\w+)*$/;
    die "'$priority' is not a valid priority number.\n" if $priority =~ /[^0-9]/;

    my $name = ( split '::', $pkg )[-1];

    # Run-time loaded classes do not get access to base class methods in the compiled code.
    _patch_methods($pkg);
    return bless { 'priority' => $priority, 'name' => $name }, $pkg;
}

# Patch base class method calls into supplied namespace to make up for compiler bug.
# 'can' check on $pkg prevents this from causing problems with defined methods or
# if the compiler bug goes away.
sub _patch_methods {
    my ($pkg) = @_;

    # Allow refs to simplify symbol table manipulation
    no strict 'refs';

    # Retrieve all names from symbol table.
    foreach my $m ( keys %{ __PACKAGE__ . '::' } ) {

        # Ignore methods that we really don't want to access from child, and non-method symbols.
        next unless $m ne 'init' and $m ne '_patch_methods' and __PACKAGE__->can($m);

        # Ignore methods that already exist on the child class
        next if eval { $pkg->can($m); };

        # Ugly, nasty code to perform on-the-fly modification of child symbol table
        my $patch = '*' . $pkg . '::' . "$m = \\&" . __PACKAGE__ . '::' . $m;
        eval $patch;
    }
}

sub check_fails {
    my ( $self, $sec_ctxt, $cpconf ) = @_;

    my $req_type = $sec_ctxt->{'request_type'} || '';
    if ( !$cpconf->{'SecurityPolicy::dnsclustering'} && $req_type eq 'dnsadmin' ) {
        return 0;
    }

    return $self->fails( $sec_ctxt, $cpconf );
}

sub fails {

    my $logger = Cpanel::Logger->new();
    $logger->invalid("The fails method should be implemented in the child class.\n");
    return;
}

sub priority {
    return $_[0]->{'priority'};
}

sub name {
    return $_[0]->{'name'};
}

#
# The child class must implement this
#
sub description {

    # Child overrides
    return;
}

sub conf_value {
    my ( $self, $cpconf, $subkey ) = @_;
    return $cpconf->{ join( '::', 'SecurityPolicy', $self->name, $subkey ) };
}

sub set_conf_value {
    my ( $self, $cpconf, $subkey, $value ) = @_;
    $cpconf->{ join( '::', 'SecurityPolicy', $self->name, $subkey ) } = $value;
    return;
}

sub conf_keys {
    my ( $self, $cpconf ) = @_;
    my $prefix = 'SecurityPolicy::' . $self->name;
    return sort map { /^\Q$prefix\E::(\w+)/ ? ($1) : () } keys %{$cpconf};
}

sub bypass {
    my ( $self, $sec_ctxt, $cpconf ) = @_;

    my $req_type = $sec_ctxt->{'request_type'} || '';
    if ( !$cpconf->{'SecurityPolicy::dnsclustering'} && $req_type eq 'dnsadmin' ) {
        return 1;
    }
    if ( !$cpconf->{'SecurityPolicy::xml-api'} && ( $req_type eq 'json' || $req_type eq 'xml' ) ) {
        return 1;
    }

    # Override in child class.
    return $self->bypass_page( $sec_ctxt, $cpconf );
}

sub bypass_page {
    my ($self) = @_;

    return;
}

sub hidden {
    return 0;
}

sub get_ui {
    my ( $self, $reqtype, @secdirs ) = @_;
    $reqtype ||= 'html';
    return $self->{'UI'}->{$reqtype} if exists $self->{'UI'}->{$reqtype};

    @secdirs = ( $security_policy_dir, $user_sec_policy_dir ) unless @secdirs;

    $reqtype = $UITYPES{$reqtype} || 'HTML';

    my $pkg       = ref $self;
    my $uimodname = "${pkg}::UI::$reqtype";
    my $mod       = $uimodname;
    $mod =~ s{::}{/}g;

    # If we don't have a defined UI module, fall back to the default.
    if ( !grep { -e "$_/$mod.pm" } @secdirs ) {
        $uimodname = "Cpanel::SecurityPolicy::Default::UI::$reqtype";
    }

    eval "require $uimodname;";
    if ($@) {
        my $logger = Cpanel::Logger->new();
        $logger->warn("Failed to load $uimodname: $@");
        return;
    }

    $self->{'UI'}->{$reqtype} = $uimodname->new($self);
    return $self->{'UI'}->{$reqtype};
}

sub get_config {
    my ( $self, @secdirs ) = @_;

    @secdirs = ( $security_policy_dir, $user_sec_policy_dir ) unless @secdirs;

    my $pkg        = ref $self;
    my $cfgmodname = "${pkg}::Config";
    my $mod        = $cfgmodname;
    $mod =~ s{::}{/}g;

    # If we don't have a defined UI module, fall back to the default.
    if ( !grep { -e "$_/$mod.pm" } @secdirs ) {
        $self->{'_config'} = undef;
        return;
    }

    eval "require $cfgmodname;";
    if ($@) {
        my $logger = Cpanel::Logger->new();
        $logger->warn("Failed to load $cfgmodname: $@");
        return;
    }

    $self->{'_config'} = $cfgmodname->new($self);
    return $self->{'_config'};
}

1;
