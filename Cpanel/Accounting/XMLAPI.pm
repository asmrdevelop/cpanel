package Cpanel::Accounting;

# cpanel - Cpanel/Accounting/XMLAPI.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use XML::Simple ();
$XML::Simple::PREFERRED_PARSER = "XML::SAX::PurePerl";

sub xmlapi_listaccts {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listaccts', \@_, [ 'search', 'searchtype' ] ) );
}

sub xmlapi_createacct {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/createacct', \@_, [ 'username', 'domain', 'password', 'plan' ] ) );
}

sub xmlapi_removeacct {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/removeacct', \@_, ['user'] ) );
}

sub xmlapi_showversion {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/version', \@_ ) );
}

sub xmlapi_version {
    goto &xmlapi_showversion;
}

sub xmlapi_applist {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/applist', \@_ ) );
}

sub xmlapi_generatessl {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_post_whmreq( '/xml-api/generatessl', \@_, [ 'host', 'pass', 'country', 'state', 'city', 'co', 'cod', 'email', 'xemail' ] ) );
}

sub xmlapi_generatessl_noemail {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_post_whmreq( '/xml-api/generatessl', \@_, [ 'host', 'pass', 'country', 'state', 'city', 'co', 'cod', 'email' ], ['noemail=1'] ) );
}

sub xmlapi_listcrts {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listcrts', \@_ ) );
}

# Variable arguments
sub xmlapi_setresellerlimits {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setresellerlimits', \@_ ) );
}

sub xmlapi_setresellerpackagelimit {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setresellerpackagelimit', \@_, [ 'user', 'package', 'allowerd', 'number', 'no_limit' ] ) );
}

sub xmlapi_setresellermainip {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setresellermainip', \@_, [ 'user', 'ip' ] ) );
}

sub xmlapi_setresellerips {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setresellerips', \@_, [ 'user', 'delegate', 'ips' ] ) );
}

sub xmlapi_setresellernameservers {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setresellernameservers', \@_, [ 'user', 'nameservers' ] ) );
}

sub xmlapi_suspendreseller {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/suspendreseller', \@_, [ 'user', 'reason', 'disallow' ] ) );
}

sub xmlapi_unsuspendreseller {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/unsuspendreseller', \@_, ['user'] ) );
}

# Variable arguments
sub xmlapi_addzonerecord {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/addzonerecord', \@_ ) );
}

# Variable arguments
sub xmlapi_editzonerecord {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/editzonerecord', \@_ ) );
}

sub xmlapi_removezonerecord {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/removezonerecord', \@_, [ 'domain', 'Line' ] ) );
}

sub xmlapi_getzonerecord {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/getzonerecord', \@_, [ 'domain', 'Line' ] ) );
}

sub xmlapi_servicestatus {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/servicestatus', \@_, ['service'] ) );
}

sub xmlapi_configureservice {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/configureservice', \@_, [ 'service', 'enabled', 'monitored' ] ) );
}

sub xmlapi_acctcounts {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/acctcounts', \@_, ['user'] ) );
}

sub xmlapi_domainuserdata {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/domainuserdata', \@_, ['domain'] ) );
}

sub xmlapi_editquota {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/editquota', \@_, [ 'user', 'quota' ] ) );
}

sub xmlapi_nvget {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/nvget', \@_, ['key'] ) );
}

# The underlying XMLAPI call allows setting multiple nvvars at once by appending
# labels to the end of the variable names... i.e. key1, value1
sub xmlapi_nvset {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_post_whmreq( '/xml-api/nvset', \@_, [ 'key', 'value' ] ) );
}

sub xmlapi_myprivs {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/myprivs', \@_ ) );
}

sub xmlapi_listzones {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listzones', \@_ ) );
}

sub xmlapi_sethostname {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/sethostname', \@_, ['hostname'] ) );
}

sub xmlapi_setresolvers {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setresolvers', \@_, [ 'nameserver1', 'nameserver2', 'nameserver3' ] ) );
}

sub xmlapi_addip {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/addip', \@_, [ 'ip', 'netmask' ] ) );
}

sub xmlapi_delip {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/delip', \@_, [ 'ip', 'ethernetdev', 'skipifshutdown' ] ) );
}

sub xmlapi_listips {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listips', \@_ ) );
}

sub xmlapi_dumpzone {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/dumpzone', \@_, ['domain'] ) );
}

sub xmlapi_listpkgs {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listpkgs', \@_ ) );
}

sub xmlapi_limitbw {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/limitbw', \@_, [ 'user', 'bwlimit' ] ) );
}

sub xmlapi_showbw {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/showbw', \@_, [ 'month', 'year', 'showres', 'search', 'searchtype' ] ) );
}

sub xmlapi_killdns {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/killdns', \@_, ['domain'] ) );
}

sub xmlapi_adddns {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/adddns', \@_, [ 'domain', 'ip', 'trueowner' ] ) );
}

sub xmlapi_changepackage {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/changepackage', \@_, [ 'user', 'pkg' ] ) );
}

sub xmlapi_modifyacct {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/modifyacct', \@_, [ 'user', 'domain', 'HASCGI', 'CPTHEME', 'LANG', 'MAXPOP', 'MAXFTP', 'MAXLST', 'MAXSUB', 'MAXPARK', 'MAXADDON', 'MAXSQL', 'shell' ] ) );
}

sub xmlapi_suspendacct {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_post_whmreq( '/xml-api/suspendacct', \@_, [ 'user', 'reason' ] ) );
}

sub xmlapi_unsuspendacct {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/unsuspendacct', \@_, ['user'] ) );
}

sub xmlapi_listsuspended {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listsuspended', \@_ ) );
}

sub xmlapi_addpkg {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/addpkg', \@_, [ 'pkgname', 'quota', 'ip', 'cgi', 'frontpage', 'cpmod', 'maxftp', 'maxsql', 'maxpop', 'maxlst', 'maxsub', 'maxpark', 'maxaddon', 'featurelist', 'hasshell', 'bwlimit' ] ) );
}

sub xmlapi_killpkg {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/killpkg', \@_, ['pkg'] ) );
}

sub xmlapi_editpkg {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/editpkg', \@_, [ 'pkgname', 'quota', 'ip', 'cgi', 'frontpage', 'cpmod', 'maxftp', 'maxsql', 'maxpop', 'maxlst', 'maxsub', 'maxpark', 'maxaddon', 'featurelist', 'hasshell', 'bwlimit' ] ) );
}

sub xmlapi_setacls {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setacls', \@_, [ 'reseller', 'acllist' ] ) );
}

sub xmlapi_terminatereseller {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/terminatereseller', \@_, [ 'reseller', 'verify' ] ) );
}

sub xmlapi_resellerstats {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/resellerstats', \@_, ['reseller'] ) );
}

sub xmlapi_setupreseller {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setupreseller', \@_, [ 'user', 'makeowner' ] ) );
}

sub xmlapi_lookupnsip {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/lookupnsip', \@_, ['nameserver'] ) );
}

sub xmlapi_listresellers {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listresellers', \@_ ) );
}

sub xmlapi_listacls {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/listacls', \@_ ) );
}

sub xmlapi_saveacllist {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/saveacllist', \@_, ['acllist'] ) );
}

sub xmlapi_unsetupreseller {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/unsetupreseller', \@_, ['user'] ) );
}

sub xmlapi_gethostname {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/gethostname', \@_ ) );
}

sub xmlapi_fetchsslinfo {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_post_whmreq( '/xml-api/fetchsslinfo', \@_, [ 'domain', 'crtdata' ] ) );
}

sub xmlapi_installssl {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_post_whmreq( '/xml-api/installssl', \@_, [ 'domain', 'user', 'cert', 'key', 'cab', 'ip' ] ) );
}

sub xmlapi_passwd {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/passwd', \@_, [ 'user', 'pass' ] ) );
}

sub xmlapi_reboot {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/reboot', \@_, ['force'] ) );
}

sub xmlapi_accountsummary_user {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/accountsummary', \@_, ['user'] ) );
}

sub xmlapi_accountsummary_domain {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/accountsummary', \@_, ['domain'] ) );
}

sub xmlapi_loadavg {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/loadavg', \@_ ) );
}

sub xmlapi_restartservice {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/restartservice', \@_, ['service'] ) );
}

sub xmlapi_setsiteip_user {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setsiteip', \@_, [ 'user', 'ip' ] ) );
}

sub xmlapi_setsiteip_domain {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/setsiteip', \@_, [ 'domain', 'ip' ] ) );
}

sub xmlapi_initializemsgcenter {
    my $self = shift;
    return XML::Simple::XMLin(
        $self->simple_get_whmreq(
            '/xml-api/initializemsgcenter', \@_,
            [ 'title', 'id' ]
        )
    );
}

sub xmlapi_createmsg {
    my $self = shift;

    # Need to perform magic to deal with the optional parameters.
    my @parm_names = (
        'title',             'updated',         'published', 'content', 'author.name', 'author.email', 'author.uri', 'contributor.name',
        'contributor.email', 'contributor.uri', 'summary'
    );

    my $extra_count = scalar(@_) - scalar(@parm_names);
    my $cat_count   = int( $extra_count / 3 + ( ( $extra_count % 3 ) && 1 ) );
    foreach my $i ( 1 .. $cat_count ) {
        push @parm_names, "category.$i.term", "category.$i.label", "category.$i.scheme";
    }

    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/createmsg', \@_, \@parm_names ) );
}

sub xmlapi_deletemsg {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/deletemsg', \@_, ['atom_id'] ) );
}

sub xmlapi_getmsgfeed {
    my $self = shift;
    return XML::Simple::XMLin( $self->simple_get_whmreq( '/xml-api/getmsgfeed', \@_, ['which'] ) );
}

1;
