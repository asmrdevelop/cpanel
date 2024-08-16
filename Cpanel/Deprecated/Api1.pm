# cpanel - Cpanel/Deprecated/Api1.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Deprecated::Api1;

use cPstrict;

=head1 NAME

C<Cpanel::Deprecated::Api1>

=head1 SYNOPSIS

    my $msg = Cpanel::Deprecated::Api1::get_unauthorized_msg_or_undef('Email', 'addpop');

=head1 DESCRIPTION

C<Cpanel::Deprecated::Api1> list of API1 modules that can not be called via API 1 external
interfaces including cpanel.pl or the TT plugin.
=cut

#----------------------------------------------------------------------

use Cpanel                                   ();
use Cpanel::Encoder::URI                     ();
use Cpanel::Server::Type::Profile            ();
use Cpanel::Server::Type::Profile::Constants ();    # PPI USE OK -- used as constant

our @deprecated_api1_modules = qw(
  Serverinfo
);

#----------------------------------------------------------------------

my %_API1_NEEDED_FOR_MAIL_NODE_PROFILE;
my %_API1_NEEDED_FOR_PARENT_ACCOUNTS;

BEGIN {

    # These lists arose from an audit done in December 2020.
    # Revise as appropriate; eventually we’ll just remote API 1
    # altogether.

    %_API1_NEEDED_FOR_MAIL_NODE_PROFILE = map { $_ => undef } (
        'Bandwidth::displaybw',
        'Cgi::phpmyadminlink',
        'LVEinfo::cpu',
        'LVEinfo::mem',
        'LVEinfo::mem_limit',
        'LVEinfo::mep',
        'LVEinfo::mep_limit',
        'LVEinfo::print_usage_overview',
        'LVEinfo::start',
        'include',
    );

    %_API1_NEEDED_FOR_PARENT_ACCOUNTS = map { $_ => undef } (
        keys(%_API1_NEEDED_FOR_MAIL_NODE_PROFILE),

        'Cgi::backuplink',
        'ClamScannar::disinfect',
        'ClamScanner::bars',
        'ClamScanner::disinfectlist',
        'ClamScanner::main',
        'ClamScanner::printScans',
        'ClamScanner::scanhomedir',
        'ImageManager::convert',
        'ImageManager::dimensions',
        'ImageManager::hdimension',
        'ImageManager::scale',
        'ImageManager::thumbnail',
        'ImageManager::wdimension',
        'LangMods::install',
        'LangMods::uninstall',
        'LangMods::update',
        'LeechProtect::disable',
        'LeechProtect::enable',
        'LeechProtect::setup',
        'LeechProtect::showpasswdfile',
        'LeechProtect::status',
        'OptimizeWS::loadoptimizesettings',
        'OptimizeWS::optimizews',
        'ProxyUtils::proxyaddress',
        'UI::confirm',
        'cPAddons::mainpg',
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $msg = get_unauthorized_msg_or_undef( $MODULE, $FUNCNAME )

Takes the API 1 module and function names (e.g., C<Email> and C<addpop>).

Returns one of:

=over

=item * A human-readable string that indicates why access to the given API 1
function is unauthorized, and what to do about it.

=item * undef, to indicate that access to the API 1 function is
authorized.

=back

=cut

sub get_unauthorized_msg_or_undef ( $module, $esub ) {
    my $cpuser_obj = \%Cpanel::CPDATA;

    my ( $msg, $allowed_hr, $is_parent_account );

    # Child accounts block API 1 entirely.
    if ( $cpuser_obj->child_workloads() ) {
        my $url = _get_api1_docs_link( $module, $esub );

        return "Child accounts cannot run API 1 functions. See this function’s documentation ($url) for a supported replacement, and call that replacement function on your account’s parent node.";
    }

    # Mail Server profile only needs to allow a handful of API 1 calls.
    elsif ( Cpanel::Server::Type::Profile::get_current_profile() eq Cpanel::Server::Type::Profile::Constants::MAILNODE ) {
        $allowed_hr = \%_API1_NEEDED_FOR_MAIL_NODE_PROFILE;
    }

    # Parent accounts should allow only those API 1 calls that
    # the UI needs.
    elsif (
        do {
            require Cpanel::LinkedNode::Worker::GetAll;
            Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_obj);
        }
    ) {
        $is_parent_account = 1;
        $allowed_hr        = \%_API1_NEEDED_FOR_PARENT_ACCOUNTS;
    }

    if ($allowed_hr) {
        my $ok = exists $allowed_hr->{$module};

        $ok ||= $esub && exists $allowed_hr->{"$module\::$esub"};

        if ( !$ok ) {
            if ($is_parent_account) {
                $msg = 'You cannot run this API 1 function.';
            }
            else {
                $msg = 'This server cannot run this API 1 function.';
            }
        }
    }

    if ($msg) {
        my $url = _get_api1_docs_link( $module, $esub );

        return "$msg See this function’s documentation ($url) for a supported replacement.";
    }

    return undef;
}

sub _get_api1_docs_link ( $module, $esub ) {

    # URI-escape these, just in case some caller passes in some
    # wonky (invalid) API module or function name, so that we
    # at least have a well-formed URL. (As it happens cpsrvd actually
    # strips out “weird” characters, so this may well never make a
    # difference, but it doesn’t hurt.)
    $_ = Cpanel::Encoder::URI::uri_encode_str($_) for ( $module, $esub );

    # documentation.cpanel.net is slated for decommissioning at an
    # indefinite point in the future, but once that happens there should
    # still be some redirect to wherever we host API 1 documentation.
    return sprintf( 'https://documentation.cpanel.net/display/DD/cPanel+API+1+Functions+-+%s%%3a%%3a%s', $module, $esub );
}

1;
