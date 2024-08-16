package Cpanel::Email;

# cpanel - Cpanel/Email.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not warnings safe yet
#
use Try::Tiny;

use Cpanel                     ();
use Cpanel::AdminBin           ();
use Cpanel::CachedDataStore    ();
use Cpanel::Config::LoadConfig ();
use Cpanel::ConfigFiles        ();
use Cpanel::Email::Accounts    ();
use Cpanel::Email::Maildir     ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Exception          ();
use Cpanel::Locale             ();
use Cpanel::PwCache            ();
use Cpanel::SafeDir::MK        ();
use Cpanel::SafeFile           ();
use Cpanel::StringFunc::Trim   ();
use Cpanel::LoadModule         ();
use Cwd                        ();
use Cpanel::Fcntl              ();
use Cpanel::Debug              ();
use Cpanel::API                ();
use Cpanel::API::Email         ();

*listforwards       = *Cpanel::API::Email::_listforwards;
*listdforwards      = *Cpanel::API::Email::_listdforwards;
*listautoresponders = *Cpanel::API::Email::_listautoresponders;

sub countfilters    { goto &Cpanel::API::Email::_countfilters; }
sub countlists      { goto &Cpanel::API::Email::_countlists; }
sub countforwards   { goto &Cpanel::API::Email::_countforwards; }
sub countpops       { goto &Cpanel::API::Email::_countpops; }
sub countresponders { goto &Cpanel::API::Email::_countresponders; }

*VERSION  = \$Cpanel::API::Email::VERSION;
*DEBUG    = \$Cpanel::API::Email::DEBUG;
*EMAILTTL = \$Cpanel::API::Email::EMAILTTL;

my $true_func = sub { 1; };

my ( $locale, $rPOPCACHE, $APIref, $currentfilter, @MAILDOMAINS_cache );

## NOTE: not used by api2_addforward!
sub addforward {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $email, $forward, $domain, $return, $domhash ) = @_;

    return if !main::hasfeature("forwarders");
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        my $demo = $locale->maketext('Sorry, this feature is disabled in demo mode.');

        if ($return) { return ( 0, $demo ); }
        print $demo;
        return;
    }

    $forward = Cpanel::StringFunc::Trim::ws_trim($forward);

    if ( !$forward ) {
        if ($return) { return ( 0, "You must choose a destination address." ); }
        return;
    }

    # Pipe forwarders require the FileStorage role as well as
    # a non-Webmail account.
    if ( -1 != index( $forward, '|' ) ) {
        if ( $Cpanel::appname eq 'webmail' || !_filestorage_is_on() ) {
            my $err = "Invalid forward destination: [$forward]";

            if ($return) {
                return ( 0, $err );
            }
            $Cpanel::CPERROR{'email'} = $err;
            return;
        }
    }

    $locale ||= Cpanel::Locale->get_handle();

    my ( $result, $reason ) = quotatest($return);
    if ( !$result ) {
        return ( $result, $reason ) if $return;
        return;
    }

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        $email  = ( split( /\@/, $Cpanel::authuser ) )[0];
        $domain = Cpanel::API::Email::_getdomain($Cpanel::authuser);
        $forward =~ s/\|//g;
    }
    if ( !$domain ) { $domain = $Cpanel::CPDATA{'DNS'}; }

    require Cpanel::Validate::Domain::Tiny;
    require Cpanel::Validate::Domain::Normalize;
    $domain = Cpanel::Validate::Domain::Normalize::normalize($domain);
    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {

        $Cpanel::CPERROR{'email'} = $locale->maketext( '“[_1]” is not a valid domain name.', $domain ) . "\n";    # what about the 3 return's above ?
        return;
    }

    require Cpanel::Validate::EmailCpanel;
    require Cpanel::Validate::EmailLocalPart;
    if (
        !$email
        || (   !Cpanel::Validate::EmailLocalPart::is_valid($email)
            && !Cpanel::Validate::EmailCpanel::is_valid($email) )
    ) {
        $Cpanel::CPERROR{'email'} = 'The address to forward is not a valid email address.';
        return;
    }

    $forward = Cpanel::StringFunc::Trim::ws_trim($forward);

    ## ???: should the \| have a ^ anchor? The one right below does...
    if ( $forward !~ m/\@/ && $forward !~ m/\|/ && $forward !~ m/^\"/ && $forward !~ m/^:/ ) {
        if ( !( Cpanel::PwCache::getpwnam($forward) )[0] ) {
            $forward = $forward . '@' . $domain;
        }
    }

    $forward = Cpanel::StringFunc::Trim::ws_trim($forward);
    if ( $forward !~ m/^:/ && $forward !~ m/^\"/ && $forward !~ m/^\|/ ) {
        $forward =~ s/\s//g;
    }

    $forward =~ s/\;/\,/g;
    $forward =~ s/^\s*['"]([\s\w\W]+)['"]\s*$/$1/;

    # in case there is any surrounding ws after the mods following the initial ws_trim
    $forward = Cpanel::StringFunc::Trim::ws_trim($forward);

    return if !$forward;

    # Keep the supplied domain if it exists and it's one of my domains.
    my $ldom;
    ( $email, $ldom ) = split /\@/, $email;
    if ($ldom) {

        # If a domain hash is supplied, look in that hash. Otherwise, walk the domain array.
        if ($domhash) {
            $domain = $ldom if exists $domhash->{$ldom};
        }
        else {
            $domain = $ldom if grep { $ldom eq $_ } @Cpanel::DOMAINS;
        }
    }

    # if $domain is bad (IE this function returns false) it'd have been caught above
    my $aliases_obj = get_mailconfig($domain) || return;

    $email = $email . '@' . $domain;

    my $we_are_adding_a_colon_command = 0;

    require Cpanel::Validate::EmailRFC;

    if ( $Cpanel::appname eq 'webmail' ) {

        # Cpanel::Email::Aliases::save() does additional munging of the final destination.
        # That is replicated here so that validation of the actual destination is possible.
        $forward = Cpanel::StringFunc::Trim::ws_trim($forward);
        $forward =~ s/[\f\r\n]*//g;

        my $orig_forward = $forward;

        # SEC-672: Do not let things such as ":\inc\lude\:" through
        #          This is safe since we preserve the original string
        $forward =~ s/\\//g;

        if ( $forward =~ /\:\s*(?:fail|defer|blackhole|include)\s*\:/s ) {

            # Invalid forwarder types for webmail
            if ($return) {
                return ( 0, "Destination email address is invalid." );
            }
            $Cpanel::CPERROR{'email'} = 'Destination email address is invalid.';
            return;
        }

        $forward = $orig_forward;
    }

    if ( $forward =~ /^[\s"]*\:(fail|defer|blackhole|include)\:/ ) {

        # if we have one :fail: type entry then its the only one allowed since the
        # ones before it will be ignored and the ones after it will be part of the message

        $we_are_adding_a_colon_command = 1;
        $aliases_obj->remove_alias($email);

        # $aliases_obj->add($email, $forward);
    }
    elsif ( !Cpanel::Validate::EmailRFC::is_valid($forward) ) {    # email address
        $forward =~ s{([",])}{\\$1}g;
        $forward = '"' . $forward . '"';
    }

    unless ($we_are_adding_a_colon_command) {
        for my $fwd ( $aliases_obj->get_destinations($email) ) {
            if ( $fwd =~ m/^[\s"]*\:(fail|defer|blackhole|include)\:/ ) {
                $aliases_obj->delete_destination( $email => $fwd );
                $aliases_obj->delete_destination( $email, qq{"$fwd"} );    # remove same but in case the string contains surrounding quotes
            }
        }
    }

    if ( $forward =~ m/\@/ && !Cpanel::Validate::EmailRFC::is_valid($forward) ) {
        if ($return) {
            return ( 0, "Destination email address is invalid." );
        }
        return;
    }
    unless ( Cpanel::Validate::EmailRFC::is_valid($email) ) {
        if ($return) {
            return ( 0, "Source email address is invalid." );
        }
        return;
    }

    if ( $email ne $forward ) {
        $aliases_obj->add( $email => $forward );
    }
    rebuildconf($aliases_obj);

    ## case 30334: removed explicit call to ::EventHandler subsystem

    if ($return) {
        return ( 1, "$email will be forwarded to $forward" );
    }

    return;
}

## NOTE: used only by cpanel-email.pl
sub checkdefaultaddress {    ## no critic qw(Subroutines::RequireArgUnpacking)
    if ( !main::hasfeature("defaultaddress") ) { return (); }
    my $domain = $_[0];

    my $emailconf = get_mailconfig($domain) || return;
    my $email     = $emailconf->get_default_destination();

    $email = _resolveemails($email);

    get_mailconfig($domain) || return;
    $emailconf->set_default_destination($email);
    rebuildconf($emailconf);

    return 0;
}

## NOTE: not used by api2_setdefaultaddress
sub setdefaultaddress {    ## no critic qw(Subroutines::RequireArgUnpacking)
    if ( !main::hasfeature("defaultaddress") ) { return (); }
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        $locale ||= Cpanel::Locale->get_handle();
        print $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my ( $email, $domain ) = @_;

    $locale ||= Cpanel::Locale->get_handle();

    require Cpanel::Validate::Domain::Tiny;
    require Cpanel::Validate::Domain::Normalize;
    $domain = Cpanel::Validate::Domain::Normalize::normalize($domain);
    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {

        $Cpanel::CPERROR{'email'} = $locale->maketext( '“[_1]” is not a valid domain name.', $domain ) . "\n";    # what about the 2 return's above ?
        return;
    }

    my $destemail;
    if ( $email =~ m/^\s*[\"\:\|]/ ) {
        $destemail = $email;
    }
    else {
        $destemail = _resolveemails($email);
    }

    # if $domain is bad (IE this function returns false) it'd have been caught above
    my $aliases_obj = get_mailconfig($domain) || return;
    $aliases_obj->set_default_destination($destemail);
    rebuildconf($aliases_obj);

    return 0;
}

*_find_maildirsize_file = \&Cpanel::Email::Maildir::_find_maildirsize_file;

*set_maildirsize_quota = \&Cpanel::Email::Maildir::set_maildirsize_quota;

sub fix_pop_perms {
    my @POPS = listpops();

    my $user_homedir = $Cpanel::homedir;    # make a copy because this is really a tied scalar

    foreach my $pop (@POPS) {
        my ( $email, $popdomain ) = split( /\@/, $pop );

        my $current_umask = umask();
        umask 0;
        if ( sysopen( my $create_maildirsize_fh, "$user_homedir/mail/$popdomain/$email/maildirsize", Cpanel::Fcntl::or_flags(qw( O_WRONLY O_EXCL O_CREAT )), 0640 ) ) {
            close($create_maildirsize_fh);
        }
        umask($current_umask);

        Cpanel::AdminBin::adminrun( 'mx', 'NULLIFY', $popdomain, $email );
    }
}

## NOTE: not used by api2_listpops* (confirm?)
sub listpops {
    my %OPTS = @_;

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        return ($Cpanel::authuser);
    }

    my $popaccts_ref = _managepopdbs(
        'event'       => 'fetch',
        'no_validate' => int $OPTS{'no_validate'},
        'no_disk'     => 1
    );

    my $domain;
    return map {
        $domain = $_;
        map { Cpanel::Encoder::Tiny::safe_html_encode_str($_) . '@' . $domain }
          keys %{ $popaccts_ref->{$domain}->{'accounts'} }
    } keys %{$popaccts_ref};
}

sub listpopswithdisk {
    my $tdomain     = shift;
    my $maxaccts    = shift;
    my $regex       = shift;
    my $no_validate = shift;

    if ($regex) {
        eval {
            local $SIG{'__DIE__'} = $true_func;
            $regex = qr/$regex/i;
        };
        if ( $@ || !$regex ) {
            $Cpanel::CPERROR{'email'} = 'Invalid regex';
            return;
        }
    }

    if ( $tdomain eq '' && $rPOPCACHE ) {
        return $rPOPCACHE;
    }

    my %FETCHOPTS = ( 'event' => 'fetch' );
    if ( $tdomain && $tdomain ne '' ) { $FETCHOPTS{'matchdomain'} = $tdomain; }
    if ($maxaccts)                    { $FETCHOPTS{'maxaccts'}    = $maxaccts; }
    if ($no_validate)                 { $FETCHOPTS{'no_validate'} = $no_validate; }
    my $popaccts_ref = _managepopdbs(%FETCHOPTS);

    my ( $domain, $acct );
    my @DPOPS = map {
        $domain = $_;    #safe the domain from the main map

        # Go though each login in the domain
        map { [ Cpanel::Encoder::Tiny::safe_html_encode_str($_) . '@' . $domain, $popaccts_ref->{$domain}->{'accounts'}->{$_}->{'diskused'}, $popaccts_ref->{$domain}->{'accounts'}->{$_}->{'diskquota'} ] } grep {    # only go through the keys we want
            $acct = $_ . '@' . $domain;
            !defined $regex || $acct =~ $regex;
          }
          keys %{ $popaccts_ref->{$domain}->{'accounts'} };
      }
      keys %{$popaccts_ref};

    #@DPOPS = sort { $a->[0] cmp $b->[0] } @DPOPS;
    $rPOPCACHE = \@DPOPS;

    return $rPOPCACHE;
}

sub _countdomainpops {
    my $domain = shift;
    $domain =~ s/\.\.//g;
    $domain =~ s/\///g;

    my %POPTMP;

    #print STDERR "_countdomainpops open($Cpanel::homedir/etc/${domain}/passwd)\n";

    my $pwlock = Cpanel::SafeFile::safeopen( \*PASSWD, '<', $Cpanel::homedir . '/etc/' . $domain . '/passwd' );    #safesecure2
    if ( !$pwlock ) {
        Cpanel::Debug::log_warn("Could not edit $Cpanel::homedir/etc/$domain/passwd");
        return;
    }

    while (<PASSWD>) {
        my $login = ( split( /:/, $_ ) )[0];
        $POPTMP{$login} = 1;
    }
    Cpanel::SafeFile::safeclose( \*PASSWD, $pwlock );

    return ( scalar keys %POPTMP );
}

## not clear if this is used anywhere
# deprecated, use uapi Email::enable_spam_box
sub addspambox {
    return if !main::hasfeature('spamassassin');
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        print $locale->maketext('Sorry, this feature is disabled in demo mode.');

        return;
    }
    return if !quotatest();

    # doveadm mailbox create INBOX.spam -u nick

    if ( open my $spam_fh, '>', $Cpanel::homedir . '/.spamassassinboxenable' ) {
        close $spam_fh;
    }

    return 1;
}

## not clear if this is used anywhere
### deprecated, use uapi Mailboxes::expunge_mailbox_messages mailbox=INBOX.spam
sub clearspambox {
    return if !main::hasfeature('spamassassin');

    $locale ||= Cpanel::Locale->get_handle();
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        print $locale->maketext('Sorry, this feature is disabled in demo mode.');

        return;
    }

    # Clear main account's spam box
    if ( -d $Cpanel::homedir . '/mail/.spam'
        && !-l $Cpanel::homedir . '/mail/.spam' ) {
        print $locale->maketext("Clearing Spam Box for main account.");
        _searchanddestroy( $Cpanel::homedir . '/mail/.spam' );
        print " ... Done\n";
    }

    # Clear POP accounts' spam boxes
    foreach my $domain (@Cpanel::DOMAINS) {
        next if ( !-d $Cpanel::homedir . '/mail/' . $domain );
        if ( opendir my $domain_dh, $Cpanel::homedir . '/mail/' . $domain ) {
            while ( my $buser = readdir $domain_dh ) {
                next if ( $buser =~ m{ \A [.] }xms );
                next if ( !-d "$Cpanel::homedir/mail/${domain}/${buser}/.spam" );
                next if ( -l "$Cpanel::homedir/mail/${domain}/${buser}/.spam" );
                print $locale->maketext( "Clearing Spam Box for “[_1]”.", "${buser}\@${domain}" );
                _searchanddestroy("$Cpanel::homedir/mail/${domain}/${buser}/.spam");
                unlink("$Cpanel::homedir/mail/${domain}/${buser}/maildirsize");
                print " ... Done\n";
            }
            closedir $domain_dh;
        }
    }

    return;
}

sub _searchanddestroy {
    my $dirpath = shift;
    return if ( !-d $dirpath );
    my $badunlink = 0;
    my $wanted    = sub {
        if ( -f $_ && -w _ ) {
            if ( !unlink $_ ) {
                if ( !$badunlink ) {
                    print "\n";
                    $badunlink = 1;
                }
                print "Unable to unlink $_: $!";
            }
        }
        return;
    };
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeFind');
    return Cpanel::SafeFind::finddepth( { 'wanted' => $wanted, 'no_chdir' => 1 }, $dirpath );

}

## not clear if this is used anywhere
## deprecated, use uapi Email::disable_spam_box
sub delspambox {
    return if !main::hasfeature('spamassassin');
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        print $locale->maketext('Sorry, this feature is disabled in demo mode.');

        return;
    }
    return unlink $Cpanel::homedir . '/.spamassassinboxenable';
}

sub listmx {
    my $rentries = Cpanel::API::Email::_listmx( $Cpanel::CPDATA{'DNS'} );
    print $rentries->{ $Cpanel::CPDATA{'DNS'} }->{'entries'}->[0]->{'mxentry'};
    return;
}

sub listmxs {
    my $mxdata_ref = Cpanel::API::Email::_listmxs();
    foreach my $domain ( sort keys %{$mxdata_ref} ) {
        print "<tr><td>$domain</td><td>";
        print "<table><tr><th>Priority</th><th>Entry</th></tr>";
        foreach my $entry ( @{ $mxdata_ref->{$domain}->{'entries'} } ) {
            print "<tr><td>" . $entry->{'priority'} . "</td><td>" . $entry->{'mxentry'} . "</td></tr>";
        }
        print "</table>";
        print "</td></tr>\n";
    }
    return;
}

sub api2_getalwaysaccept {
    my %OPTS = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Email::MX');
    my $domain = $OPTS{'domain'};
    if ($domain) {
        return [
            {
                'domain'       => $domain,
                'alwaysaccept' => Cpanel::Email::MX::does_alwaysaccept($domain),
                'mxcheck'      => Cpanel::Email::MX::get_mxcheck_configuration($domain)
            }
        ];
    }
    else {
        my @RSD;
        foreach $domain (@Cpanel::DOMAINS) {
            push @RSD,
              {
                'domain'       => $domain,
                'alwaysaccept' => Cpanel::Email::MX::does_alwaysaccept($domain),
                'mxcheck'      => Cpanel::Email::MX::get_mxcheck_configuration($domain)
              };
        }
        return \@RSD;
    }
}

## API1 tag, but no known calls
sub setmxaccept {
    my ( $dns, $mxcheck ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Email::MX');
    my $results_arrayref = api2_setalwaysaccept( 'domain' => $dns, 'mxcheck' => $mxcheck );
    my $results          = $results_arrayref->[0];
    if ( ref $results eq 'HASH' ) {
        my %RES = %{$results};
        my ( $set, $status, $method, $warnings ) = Cpanel::Email::MX::get_mxcheck_messages( $dns, $RES{'checkmx'} );
    }
    else {
        $Cpanel::CPERROR{'email'} = "Invalid data returned from mxadmin";
    }
    return 1;
}

## API1 tag; x3 uses the api2_ version
sub delmx {
    my ( $dns, $oldmx, $priority ) = @_;
    $Cpanel::context = 'email';
    return if !main::hasfeature('changemx');
    Cpanel::LoadModule::load_perl_module('Cpanel::Email::MX');
    if ( !$dns ) {
        $Cpanel::CPERROR{'email'} = 'You must provide at least one mx entry to delete.';
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        print $locale->maketext('Sorry, this feature is disabled in demo mode.');

        return;
    }

    my $results = Cpanel::AdminBin::adminfetchnocache( 'mx', '', 'DELETE', 'storable', $dns, $oldmx, ( $priority || 0 ) );
    if ( ref $results eq 'HASH' ) {
        my %RES = %{$results};
        my ( $set, $status, $method, $warnings ) = Cpanel::Email::MX::get_mxcheck_messages( $dns, $RES{'checkmx'} );
    }
    else {
        $Cpanel::CPERROR{'email'} = "Invalid data returned from mxadmin";
    }
    return 1;
}

sub addmx {
    return _setmx( 'ADD', @_ );
}

sub changemx {
    return _setmx( 'CHANGE', @_ );
}

sub _setmx {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $op, $dns, $newmx, $priority, $alwaysaccept, $oldmx, $oldpriority ) = @_;
    $Cpanel::context = 'email';
    return if !main::hasfeature('changemx');
    Cpanel::LoadModule::load_perl_module('Cpanel::Email::MX');
    if ( !$dns || !$newmx ) {
        $Cpanel::CPERROR{'email'} = 'You must provide a new mx entry.';
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        print $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my $results = Cpanel::AdminBin::adminfetchnocache( 'mx', '', $op, 'storable', $dns, $newmx, ( $priority || 0 ), ( $alwaysaccept || 0 ), $oldmx, $oldpriority );
    if ( ref $results eq 'HASH' ) {
        my %RES = %{$results};
        my ( $set, $status, $method, $warnings ) = Cpanel::Email::MX::get_mxcheck_messages( $dns, $RES{'checkmx'} );
    }
    else {
        $Cpanel::CPERROR{'email'} = "Invalid data returned from mxadmin";
    }
    return 1;
}

## work horse for listmaildomainsoptndef, used many places in x3
sub listmaildomains {
    return map { $_->{'domain'} } @{ _listmaildomains() };
}

## see above re: &listmaildomains
sub _listmaildomains {
    if ( !@MAILDOMAINS_cache ) {
        if ( $Cpanel::appname eq 'webmail' ) {
            $Cpanel::CPVAR{'maildomainscount'} = 1;
            @MAILDOMAINS_cache = ( { 'domain' => Cpanel::API::Email::_getdomain($Cpanel::authuser) } );
        }
        else {

            # Filter out wildcard domains before sorting.
            @MAILDOMAINS_cache = map { { 'domain' => $_ } } sort grep { !/\*/ } @Cpanel::DOMAINS;
            $Cpanel::CPVAR{'maildomainscount'} = scalar @MAILDOMAINS_cache;
        }
    }
    return \@MAILDOMAINS_cache;
}

## no known tags/callers
sub api2_clearpopcache {
    my $popaccts_ref = _managepopdbs( 'event' => 'fetch', 'ttl' => 1 );

    return [ { 'status' => 1 } ];
}

## no known tags/callers
sub api2_listpopssingle {
    return api2_listpops( 'skip_main' => 1, @_ );
}

## no known tags/callers
sub api2_listpopswithimage {
    my $popref = api2_listpops( 'skip_main' => 1, @_ );
    push @$popref,
      {
        'login' => "<img src=\"/frontend/$Cpanel::CPDATA{'RS'}/images/mainacct.jpg\">",
        'email' => $Cpanel::user
      };
    return $popref;
}

sub listfilterbackups {
    for my $domain ( sort @Cpanel::DOMAINS ) {
        next if ( $domain =~ /\*/ );
        next if ( !-e "$Cpanel::ConfigFiles::VFILTERS_DIR/$domain" );
        print "<a href=\"/getfilterbackup/filter-$domain.gz\">$domain</a><br> \n";
    }
    return;
}

##############################
## UTILITY API CALLS

## DEPRECATED!
sub api2_fetchcharmaps {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "fetch_charmaps", { 'api.quiet' => 1 } );
    return ( $result->data() || [] );
}

## DEPRECATED!
sub api2_list_system_filter_info {
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_system_filter_info", { 'api.quiet' => 1 } );
    return $result->data();
}

## DEPRECATED!
sub api2_listmaildomains {
    ## 'skipmain' option still supported, but no known use of
    my %CFG    = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_mail_domains", { 'api.quiet' => 1 } );
    my @rv     = @{ $result->data() };
    if ( $CFG{'skipmain'} ) {
        @rv = ( grep { $_->{'domain'} ne $Cpanel::CPDATA{'DNS'} } @rv );
    }
    $Cpanel::CPVAR{'maildomainscount'} = scalar @rv;
    return \@rv;
}

## DEPRECATED!
sub printdomainoptions {
    my ( $select, $add_www, $include_wildcard ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_mail_domains", { select => $select, add_www => $add_www, include_wildcard => $include_wildcard } );

    # Print can be expensive when we have lots of domains due to tied IO::Scalar, so just do it once
    print join(
        '',
        map { qq(<option ) . ( $_->{'select'} ? 'selected="selected" ' : '' ) . qq(value="$_->{'domain'}">$_->{'domain'}</option>) } @{ $result->data() }
    );
    return;
}

## DEPRECATED!
sub listmaildomainsoptndef {
    my ($select) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_mail_domains", { select => $select, include_wildcard => 0 } );

    my @DOMAINS = @{ $result->data() };
    ## not sure if this is needed, but _listmaildomains does it
    $Cpanel::CPVAR{'maildomainscount'} = scalar @DOMAINS;

    foreach my $q (@DOMAINS) {
        my $select = ( $q->{'select'} ? 'selected="selected" ' : '' );
        print qq(<option value="$q->{'domain'}" $select>$q->{'domain'}</option>\n);
    }
    return;
}

## DEPRECATED!
sub listmaildomainsopt {
    my ($select) = @_;
    if ( $select eq '' ) { $select = $Cpanel::CPDATA{'DNS'}; }
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_mail_domains", { select => $select, include_wildcard => 0 } );

    my @MDOMAINS = @{ $result->data() };
    foreach my $q (@MDOMAINS) {
        my $select = ( $q->{'select'} ? 'selected="selected" ' : '' );
        print qq(<option value="$q->{'domain'}" $select>$q->{'domain'}</option>\n);
    }
    return;
}

##############################
## EMAIL ACCOUNTS

## DEPRECATED!
## used currently by x3's mail/filters/managefilters.html page
sub api2_listpops {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_pops", \%CFG );
    return unless $result->status();
    return $result->data();
}

## DEPRECATED!
sub api2_listpopswithdisk {
    my %CFG    = ( @_, 'api.quiet' => 1, 'api2_state_key' => 'Cpanel::Email::listpopswithdisk' );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_pops_with_disk", \%CFG );
    return unless $result->status();
    return $result->data();
}

## DEPRECATED!
sub mainacctdiskused {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_main_account_disk_usage" );
    print $result->data();
}

## DEPRECATED!
sub api2_getdiskusage {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_disk_usage", \%OPTS );
    my @RSD    = ( $result->data() );
    return @RSD;
}

## NOTE: only used by the mail/pops_noscript.html; not converting
sub api2_checkmaindiscard {
    $Cpanel::CPVAR{'maindiscard'} = 1;

    foreach my $domain (@Cpanel::DOMAINS) {
        my $defaddr = defaultaddress($domain);
        if ( $defaddr !~ m/(?:\/dev\/null|:fail:|:blackhole:)/ ) {
            $Cpanel::CPVAR{'maindiscard'} = 0;
            last();
        }
    }

    my @RSD;
    push( @RSD, { 'status' => $Cpanel::CPVAR{'maindiscard'} } );
    return @RSD;
}

## DEPRECATED!
## former work horse for api2_addpop; and used by the no javascript email accounts pages
#
#  The return from addpop is somewhat complicated.
#  If the parameter $return is false, addpop returns
#    - undef, on failure
#    - 0, otherwise
#  If the parameter $return is true, addpop returns a list
#    - boolean value: 1 for success, 0 for failure.
#    - string: if the boolean was true, the email address, otherwise an error message.
## DEPRECATED!
sub addpop {
    ## note: per case 30334, $skipevent can be removed here and in all its callers
    my ( $email, $password, $quota, $domain, $skipevent, $return, $skipclear, $skipupdatedb ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "add_pop", { email => $email, password => $password, quota => $quota, domain => $domain, skipupdatedb => $skipupdatedb } );

    ## ensure the above comment and this code stays in sync
    ## To be honest, I don't know when $return is 1 anymore; api2_addpop used to call addpop
    ##   (this subroutine) with $return=1. Essentially, $return prevents display. This concern
    ##   is eliminated with the Unified API and Template Toolkit. As such, api2_addpop calls
    ##   API's add_pop, and the 'return' parameter has been removed.
    if ( !$return ) {
        print $result->data() if $result->status();
        if ( !$result->status() ) {
            return;
        }
        return 0;
    }
    else {
        my $message = $result->status() ? $result->data() : $result->errors_as_string();
        return ( $result->status(), $message );
    }
}

## DEPRECATED!
sub api2_addpop {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated(
        "Email",
        "add_pop",
        {
            email              => $OPTS{email}, password => $OPTS{password},
            quota              => $OPTS{quota}, domain   => $OPTS{domain}, skip_update_db => 0,
            send_welcome_email => $OPTS{send_welcome_email},
            'api.quiet'        => 1
        }
    );
    my $reason = $result->status() ? $result->messages_as_string() : $result->errors_as_string();
    my @RSD    = ( { 'result' => $result->status, 'reason' => $reason } );
    return @RSD;
}

## DEPRECATED!
sub api2_delpop {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_pop", { email => $OPTS{'email'}, domain => $OPTS{'domain'}, 'api.quiet' => 1 } );

    my $RS = {
        result => $result->status(),
        reason => $result->status() ? 'OK' : $result->errors_as_string()
    };
    my $rawout = $result->messages_as_string();
    if ( defined $rawout ) {
        $RS->{'rawout'} = $rawout;
    }
    my @RSD;
    push @RSD, $RS;
    return @RSD;
}

## DEPRECATED!
## former work horse of api2_delpop; and used by the no javascript email accounts pages
sub delpop {
    my ( $email, $flags, $domain, $skip_quota, $skipevent, $quiet ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_pop", { email => $email, flags => $flags, domain => $domain, skip_quota => $skip_quota } );

    ## note: not sure $quiet is ever 1 anymore. see note in addpop re: $return, a variable
    ##   which served the same purpose

    ## note: the inconsistencies in these legacy return signatures is really startling
    if ( $result->status() ) {
        return 0 unless $quiet;
        return 1, undef, $result->messages_as_string();
    }
    elsif ( !$result->status() ) {
        return unless $quiet;
        return 0, $result->errors_as_string();
    }
}

## DEPRECATED!
sub api2_passwdpop {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "passwd_pop", \%OPTS );
    my @RSD;
    push @RSD, { 'result' => $result->status(), 'reason' => $result->status() ? $result->messages_as_string() : $result->errors_as_string };
    return @RSD;
}

## DEPRECATED!
## work horse for api2_passwdpop; and used by the no javascript email accounts pages
sub passwdpop {
    ## $quota is part of the signature, but no idea why; never used
    my ( $email, $password, $quota, $domain, $quiet ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "passwd_pop", { email => $email, password => $password, domain => $domain } );
    if ( $result->status() ) {
        return 0 unless $quiet;
        return 1;
    }
    else {
        return unless $quiet;
        return 0, $result->errors_as_string();
    }
}

## DEPRECATED!
## used by the no-javascript x3
sub getpopquota {
    my ( $email, $domain, $as_bytes ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_pop_quota", { email => $email, domain => $domain, as_bytes => $as_bytes } );
    return $result->data() if $result->status();
    return;
}

## DEPRECATED!
sub api2_editquota {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "edit_pop_quota", \%OPTS );
    my @RSD;
    push @RSD, { 'result' => $result->status(), 'reason' => $result->status() ? $result->messages_as_string() : $result->errors_as_string };
    return @RSD;
}

## DEPRECATED!
## former work horse for api2_editquota; and used by the no javascript email pages
sub editquota {
    my ( $email, $domain, $quota, $quiet ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "edit_pop_quota", { email => $email, domain => $domain, quota => $quota } );

    if ( $result->status() ) {
        return unless $quiet;
        return 1;
    }
    else {
        return unless $quiet;
        return 0, $result->errors_as_string();
    }
}

## DEPRECATED!
sub checkfastmail {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "check_fastmail" );
    return $Cpanel::CPVAR{'fastmail'} = $result->data();
}

sub _verify_emailarchive_tweak {

    if ( !$Cpanel::CONF{"emailarchive"} ) {
        $locale ||= Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('You do not have permission to access Email Archiving.');
        return;
    }

    return 1;
}

sub api2_set_archiving_default_configuration {
    my %OPTS = @_;

    return if !_verify_emailarchive_tweak();

    my $cpanelDir = "$Cpanel::homedir/.cpanel";
    if ( !-e $cpanelDir ) {
        Cpanel::SafeDir::MK::safemkdir( $cpanelDir, '0700' );
    }

    require Cpanel::Email::Archive;
    my $defaultConfig = Cpanel::Email::Archive::_get_archiving_default_configuration();
    $defaultConfig ||= {};

    $locale ||= Cpanel::Locale->get_handle();

    my @RETURN;

    my $email_archive_types = Cpanel::Email::Archive::fetch_email_archive_types();
    foreach my $direction ( keys %{$email_archive_types} ) {
        if ( length $OPTS{$direction} ) {    # ignore empty entries
            my $statusMessage =
              exists $defaultConfig->{$direction}
              ? $locale->maketext( 'Updated the default archive configuration for “[_1]”.', $Cpanel::user )
              : $locale->maketext( 'Enabled the default archive configuration for “[_1]”.', $Cpanel::user );

            $defaultConfig->{$direction} = int $OPTS{$direction};
            push @RETURN, { 'direction' => $direction, 'retention_period' => int $OPTS{$direction}, 'enabled' => 1, 'status' => 1, 'statusmsg' => $statusMessage };
        }
        elsif ( exists $defaultConfig->{$direction} ) {
            delete $defaultConfig->{$direction};
            push @RETURN, { 'direction' => $direction, 'retention_period' => -1, 'enabled' => 0, 'status' => 1, 'statusmsg' => $locale->maketext( 'Disabled the default archive configuration for “[_1]”.', $Cpanel::user ) };
        }
        else {
            push @RETURN, { 'direction' => $direction, 'retention_period' => -1, 'enabled' => 0, 'status' => 1, 'statusmsg' => $locale->maketext( 'Skipped the default archive configuration for “[_1]”.', $Cpanel::user ) };
        }
    }

    Cpanel::CachedDataStore::store_ref( Cpanel::Email::Archive::get_archiving_default_config_file_path(), $defaultConfig );

    return \@RETURN;
}

sub api2_get_archiving_default_configuration {

    return if !_verify_emailarchive_tweak();

    require Cpanel::Email::Archive;
    my $defaultConfig = Cpanel::Email::Archive::_get_archiving_default_configuration();

    my $email_archive_types = Cpanel::Email::Archive::fetch_email_archive_types();

    my @RETURN;
    foreach my $direction ( keys %{$email_archive_types} ) {
        if ( $defaultConfig && exists $defaultConfig->{$direction} && length $defaultConfig->{$direction} ) {
            push @RETURN, { 'direction' => $direction, 'retention_period' => int $defaultConfig->{$direction}, 'enabled' => 1 };
        }
        else {
            push @RETURN, { 'direction' => $direction, 'retention_period' => undef, 'enabled' => 0 };
        }
    }
    return \@RETURN;
}

sub api2_set_archiving_configuration {
    my %OPTS = @_;

    return if !_verify_emailarchive_tweak();

    my $domainString = $OPTS{'domains'};
    if ( $domainString =~ tr{/}{} ) {
        $locale ||= Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( '“[_1]” cannot contain the following character: [_2]', 'domains', '/' );
        return;
    }

    my @domains = split( /,/, $domainString );

    my @invalidDomains;
    foreach my $domain (@domains) {
        $domain =~ s/^\s+//;
        $domain =~ s/\s+$//;
        if ( !grep { $_ eq $domain } @Cpanel::DOMAINS ) {
            push @invalidDomains, $domain;
        }
    }

    if ( scalar @invalidDomains ) {
        $locale ||= Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'The following domains do not exist in your account: [_1]', join( ', ', @invalidDomains ) );
        return;
    }

    require Cpanel::Email::Archive;
    my $email_archive_types = Cpanel::Email::Archive::fetch_email_archive_types();

    my @RETURN;
    foreach my $domain (@domains) {
        Cpanel::Email::Archive::_set_archiving_configuration( $domain, $email_archive_types, \%OPTS, \@RETURN );
    }
    return \@RETURN;
}

sub api2_get_archiving_configuration {
    my %OPTS = @_;

    return if !_verify_emailarchive_tweak();

    my $regex;

    # Peeking at API2 arguments is a pretty ugly hack
    # and should be avoided whenever possible.
    my @filter_sort_columns        = map  { $OPTS{$_} } grep { m{api2_(?:filter|sort)_column} } keys %OPTS;
    my $filter_or_sort_by_diskused = grep { m{diskused}i } @filter_sort_columns;
    my $get_disk_usage             = 0;

    if (   $OPTS{'api2_paginate'}
        && $filter_or_sort_by_diskused ) {    #AKA NEED DISKUSAGE FOR ALL DOMAINS
        $get_disk_usage = 1;
    }

    require Cpanel::Email::Archive;
    $locale ||= Cpanel::Locale->get_handle();
    if ( $OPTS{'regex'} ) {
        eval {
            local $SIG{'__DIE__'} = sub { return };
            $regex = qr/$OPTS{'regex'}/i;
        };
        if ( !$regex ) {
            $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('Invalid Regex');
            return;
        }
    }
    my @RESULTS;
    my ( $enabled, $domain_result, $archive_cfg );

    my $email_archive_types_hashref = Cpanel::Email::Archive::fetch_email_archive_types();
    my @email_archive_types         = sort keys %{$email_archive_types_hashref};
    my $domain_has_at_least_one_archive_type;
    foreach my $dom ( @{ _listmaildomains() } ) {
        if ( $regex && $dom->{'domain'} !~ $regex ) { next; }
        if ( $OPTS{'domain'} && $dom->{'domain'} !~ m/^\Q$OPTS{'domain'}\E$/ ) {
            next;
        }
        $domain_result                        = { 'domain' => $dom->{'domain'} };
        $domain_has_at_least_one_archive_type = 0;
        foreach my $archive_type (@email_archive_types) {
            if ( $enabled = ( -e "$Cpanel::homedir/etc/$dom->{'domain'}/archive/$archive_type" ) ? 1 : 0 ) {
                $archive_cfg = Cpanel::Config::LoadConfig::loadConfig( "$Cpanel::homedir/etc/$dom->{'domain'}/archive/$archive_type", -1, ':\s+' );
            }
            $domain_result->{ 'archive_' . $archive_type }                  = $enabled;
            $domain_result->{ 'archive_' . $archive_type . '_retain_days' } = $enabled ? $archive_cfg->{'retention_period'} : undef;
            $domain_has_at_least_one_archive_type                           = 1;
        }
        if ($domain_has_at_least_one_archive_type) {
            $domain_result->{'has_archive'} = 1;
            if ($get_disk_usage) {
                require Cpanel::Email::DiskUsage;
                $domain_result->{'diskused'} = Cpanel::Email::DiskUsage::get_disk_used( '_archive', $domain_result->{'domain'} );
            }
        }
        push @RESULTS, $domain_result;
    }
    return \@RESULTS;
}

sub api2post_get_archiving_configuration {
    my %OPTS    = @_;
    my $dataref = $OPTS{'dataref'};

    return if !_verify_emailarchive_tweak();

    require Cpanel::Email::DiskUsage;

    # Splice in the disk usage updates for only the domains we are actually fetching
    foreach my $entry (@$dataref) {
        next if !$entry->{'has_archive'} || exists $entry->{'diskused'};
        $entry->{'diskused'} = Cpanel::Email::DiskUsage::get_disk_used( '_archive', $entry->{'domain'} );
    }
    return;
}

sub api2_get_archiving_types {
    return if !_verify_emailarchive_tweak();
    require Cpanel::Email::Archive;
    return [ Cpanel::Email::Archive::fetch_email_archive_types() ];
}

##############################
## WEBMAIL

## uAPI: does not seem to be used; not converting
sub check_roundcube {
    if ( -e '/usr/local/cpanel/base/3rdparty/roundcube' ) {
        $Cpanel::CPVAR{'roundcube'} = '/3rdparty/roundcube';
    }

    if ( -e '/usr/local/cpanel/base/roundcube' ) {
        $Cpanel::CPVAR{'roundcube'} = '/roundcube';
    }
    return;
}

## DEPRECATED!
sub getmailserver {
    my ($account) = @_;
    my $result = Cpanel::API::wrap_deprecated(
        "Email", "get_webmail_settings",
        { account => $account }
    );
    print $result->data()->{'domain'};
    return '';
}

## DEPRECATED!
sub getmailserveruser {
    my ($account) = @_;
    my $result = Cpanel::API::wrap_deprecated(
        "Email", "get_webmail_settings",
        { account => $account }
    );
    print Cpanel::Encoder::Tiny::safe_html_encode_str( $result->data()->{'user'} );
    return '';
}

## DEPRECATED!
sub hasmaildir {
    Cpanel::Debug::log_deprecated('Cpanel::Email::hasmaildir is deprecated.');

    ## no args
    print '1';
    return '1';
}

##############################
## SPAM ASSASSIN
## DEPRECATED!
sub spamstatus {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_spam_settings" );
    return unless $result->status();

    $locale ||= Cpanel::Locale->get_handle();

    my $settings = $result->data();
    $Cpanel::CPVAR{'spamstatus'} = $settings->{'spam_enabled'};

    if ( $settings->{'spam_enabled'} ) {
        print $locale->maketext('Enabled');
        $Cpanel::CPVAR{'spamstatusnotchangeable'} = !$settings->{'spam_status_changeable'};
        return 1;
    }

    print $locale->maketext('Disabled');
    return;
}

## DEPRECATED!
sub spamboxstatus {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_spam_settings" );
    return unless $result->status();

    $locale ||= Cpanel::Locale->get_handle();

    my $settings = $result->data();
    if ( $settings->{'spam_box_enabled'} ) {
        $Cpanel::CPVAR{'spamboxenabled'} = 1;
        print $locale->maketext('Enabled');
        return 1;
    }

    print $locale->maketext('Disabled');
    return;
}

## DEPRECATED!
sub has_spam_as_acl {
    my ($quiet) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_spam_settings", $quiet ? { 'api.quiet' => $quiet } : () );
    return unless $result->status();

    my $settings = $result->data();

    $Cpanel::CPVAR{'rewrites_subjects'} = $settings->{'rewrites_subjects'};
    $Cpanel::CPVAR{'spam_as_acl'}       = $settings->{'spam_as_acl'};
    return;
}

## DEPRECATED!
sub has_spam_autodelete {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_spam_settings" );
    return unless $result->status();

    my $settings = $result->data();

    $Cpanel::CPVAR{'spam_auto_delete'}       = $settings->{'spam_auto_delete'};
    $Cpanel::CPVAR{'spam_auto_delete_score'} = $settings->{'spam_auto_delete_score'};
    return;
}

sub enable_spam_autodelete {
    my $required_score = shift;
    addspamfilter($required_score);
}

## DEPRECATED!
sub disable_spam_autodelete {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "disable_spam_autodelete" );
    if ( $result->status() ) {
        $Cpanel::CPVAR{'spam_auto_delete'} = $result->data()->{'spam_auto_delete'};
    }
    return;
}

## DEPRECATED!
sub addspam {
    ## no args
    my $result = Cpanel::API::wrap_deprecated(
        "Email", "enable_spam_assassin",
        { 'api.quiet' => 1 }
    );
    print $result->messages_as_string();
    return;
}

## DEPRECATED!
sub delspam {
    ## no args
    my $result = Cpanel::API::wrap_deprecated(
        "Email", "disable_spam_assassin",
        { 'api.quiet' => 1 }
    );
    print $result->messages_as_string();
    return;
}

## DEPRECATED!
sub addspamfilter {
    my ($required_score) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "add_spam_filter", { required_score => $required_score } );
    if ( $result->status() ) {
        print $result->data()->{'filter'};
        return;
    }
    return;
}

##############################
## FORWARDERS
## DEPRECATED!
sub api2_listforwards {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_forwarders", \%CFG );
    return unless $result->status();
    return ( $result->data() || [] );
}

## DEPRECATED!
sub api2_addforward {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "add_forwarder", \%CFG );

    unless ( $result->status() ) {
        my $errors = $result->errors_as_string();
        return $errors if $errors;
        return;
    }
    return ( $result->data() || [] );
}

## DEPRECATED!
sub api2_delforward {
    my %OPTS = @_;
    my @RSD;

    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_forwarder", { address => $OPTS{'email'}, forwarder => $OPTS{'emaildest'} } );
    if ( $result->status() ) {
        push @RSD, { 'status' => '1', 'statusmsg' => 'OK' };
    }
    else {
        push @RSD, { 'status' => '0', 'statusmsg' => 'Failed to delete forwarder.' };
    }

    return @RSD;
}

## DEPRECATED!
sub delforward {
    my ( $address, $forwarder ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_forwarder", { address => $address, forwarder => $forwarder } );
    ## NOTE: used to "return" or "return 0", very inconsistently
    return;
}

## DEPRECATED!
sub api2_listaliasbackups {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_forwarders_backups", { 'api.quiet' => 1 } );
    return ( $result->data() || [] );
}

##############################
## DOMAIN FORWARDERS
## DEPRECATED!
sub api2_listdomainforwards {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_domain_forwarders", \%CFG );
    return ( $result->data() || [] );
}

## DEPRECATED!
sub adddforward {
    my ( $domain, $destdomain ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "add_domain_forwarder", { domain => $domain, destdomain => $destdomain } );
    return;
}

## DEPRECATED!
sub api2_adddomainforward {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "add_domain_forwarder", \%OPTS );

    my $status = $result->status();
    return [
        {
            'domain'     => $OPTS{'domain'},
            'destdomain' => $OPTS{'destdomain'},
            'status'     => $status,
            'statusmsg'  => $status
            ? $result->messages_as_string()
            : $result->errors_as_string(),
        }
    ];
}

## DEPRECATED!
sub deldforward {
    my ($domain) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_domain_forwarder", { domain => $domain } );
    ## note: keep in mind, &wrap_deprecated takes care of the output of error messages implicitly
    return;
}

##############################
## AUTO RESPONDERS
## DEPRECATED!
sub api2_listautoresponders {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_auto_responders", \%CFG );
    return unless $result->status();
    return ( $result->data() || [] );
}

## DEPRECATED!
sub api2_fetchautoresponder {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_auto_responder", \%CFG );
    ## this is correct: get_auto_responder returns a hash; callers from this context expect an AoH
    my @AoH = $result->data();
    return @AoH;
}

## DEPRECATED! use API's get_charsets and paint via Template Toolkit (see auto_responder.tt)
#The hyphen in "utf-8" is necessary in some contexts!
sub getarscharset {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $chset = _getarscharset(@_) || 'utf-8';
    require Cpanel::Locale::Utils::Charmap;
    my @CHARMAPS = Cpanel::Locale::Utils::Charmap::get_charmap_list( 0, 1 );    #no aliases
    my $selected;
    foreach ( sort @CHARMAPS ) {
        $selected = ( $_ eq $chset ) ? 'selected="selected"' : q{};
        print "<option $selected>$_</option>\n";
    }
    return $chset;
}

sub _getarscharset {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $email = $_[0];
    my $chset = $_[1] || '';
    if ($chset) { $chset =~ s/[^\w\-\_\.]//g; }

    return $chset if $chset;

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        $email = $Cpanel::authuser;
    }

    $email =~ s/\.\.//g;
    $email =~ tr{/}{}d;
    return '' if !$email || !-e "$Cpanel::homedir/.autorespond/$email";

    my $alock = Cpanel::SafeFile::safeopen( \*AUTORES, '<', "$Cpanel::homedir/.autorespond/$email" );    #safesecure2
    if ( !$alock ) {
        Cpanel::Debug::log_warn("Could not read from $Cpanel::homedir/.autorespond/$email");
        return;
    }
    while (<AUTORES>) {
        if (/charset=(\S+)/i) {
            $chset = $1;
        }
    }
    Cpanel::SafeFile::safeclose( \*AUTORES, $alock );
    return $chset;
}

## DEPRECATED! see Email's get_auto_responder
sub getarsinterval {
    my $interval = getarsconfig( 'interval', @_ );
    return $interval;
}

## DEPRECATED! see Email's get_auto_responder
sub getarsstart {
    my $start = getarsconfig( 'start', @_ );
    return $start;
}

## DEPRECATED! see Email's get_auto_responder
sub getarsstop {
    my $stop = getarsconfig( 'stop', @_ );
    return $stop;
}

## DEPRECATED! only needed because API1+2 tags do not easily enable variable capture
sub getarsconfig {
    my ( $configvarname, $autoresponder ) = @_;

    # Note following call might be no-op, i.e., if hash
    # was loaded previously.
    my $arsconf = Cpanel::API::Email::_load_autorespond_conf_from_file($autoresponder);

    # Every value in the hash is now "guaranteed"
    # to be either a valid value fetched from the config file, or a sane,
    # predefined default.
    return $arsconf->{$configvarname};
}

## DEPRECATED! see Email's get_auto_responder
sub getarsfrom {
    my $email = $_[0];

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        $email = $Cpanel::authuser;
    }

    my $from = '';

    $email =~ s/\.\.//g;
    $email =~ s/\///g;
    if ( !$email ) { return ''; }

    my $alock = Cpanel::SafeFile::safeopen( \*AUTORES, '<', "$Cpanel::homedir/.autorespond/$email" )
      || return;    #safesecure2
    while (<AUTORES>) {
        if (/^from: (.*)/i) {
            $from = $1;
            last;
        }
    }
    Cpanel::SafeFile::safeclose( \*AUTORES, $alock );
    $from =~ s/\<+.*$//g;
    $from =~ s/\"//g;
    $from =~ s/\s$//g;
    return $from;
}

## DEPRECATED! see Email's get_auto_responder
sub getarssubject {
    my $email = $_[0];

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        $email = $Cpanel::authuser;
    }

    my $subject = '';

    $email =~ s/\.\.//g;
    $email =~ s/\///g;
    if ( !$email ) { return ''; }

    my $alock = Cpanel::SafeFile::safeopen( \*AUTORES, "<", "$Cpanel::homedir/.autorespond/$email" )
      || return;    #safesecure2
    while (<AUTORES>) {
        if (/^subject: (.*)/i) {
            $subject = $1;
            last;
        }
    }
    Cpanel::SafeFile::safeclose( \*AUTORES, $alock );

    if ( $subject eq '' ) { $subject = 'Re: %subject%'; }

    return Cpanel::Encoder::Tiny::angle_bracket_encode($subject);
}

## DEPRECATED! see Email's get_auto_responder
sub getarshtml {
    my $email = $_[0];

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        $email = $Cpanel::authuser;
    }

    my $html = 0;

    $email =~ s/\.\.//g;
    $email =~ s/\///g;
    if ( !$email ) { return ''; }

    my $alock = Cpanel::SafeFile::safeopen( \*AUTORES, '<', "$Cpanel::homedir/.autorespond/$email" )
      || return;    #safesecure2
    while (<AUTORES>) {
        if (/^content-type: text\/html/i) {
            $html = 1;
            last;
        }
    }
    Cpanel::SafeFile::safeclose( \*AUTORES, $alock );

    return $html;
}

## DEPRECATED! see Email's get_auto_responder
sub getarsbody {
    my $email = $_[0];

    if ( $Cpanel::appname eq 'webmail' ) {

        #
        # SECURITY: Do not let the webmail user change anything but their own account
        #

        $email = $Cpanel::authuser;
    }

    my $inbody    = 0;
    my $bodycount = 0;
    my $body      = '';

    $email =~ s/\.\.//g;
    $email =~ s/\///g;
    if ( !$email ) { return ''; }

    my $alock = Cpanel::SafeFile::safeopen( \*AUTORES, '<', "$Cpanel::homedir/.autorespond/$email" )
      || return "";    #safesecure2
    while (<AUTORES>) {
        if ($inbody) {
            $bodycount++;
            $body = $body . $_;
            if ( $bodycount > 3500 ) { last; }
        }
        else {
            if (/^$/) {
                $inbody = 1;
            }
        }
    }
    Cpanel::SafeFile::safeclose( \*AUTORES, $alock );

    return Cpanel::Encoder::Tiny::safe_html_encode_str($body);
}

## DEPRECATED!
sub addautoresponder {
    my ( $email, $from, $subject, $body, $domain, $is_html, $charset, $interval, $start, $stop ) = @_;
    my $result = Cpanel::API::wrap_deprecated(
        "Email",
        "add_auto_responder",
        {
            email       => $email,   from                       => $from,     subject => $subject,
            body        => $body,    domain                     => $domain,   is_html => $is_html,
            charset     => $charset, interval                   => $interval, start   => $start, stop => $stop,
            'api.quiet' => 1,        'api.html_encode_messages' => 0,
        }
    );
    return $result->status();
}

## DEPRECATED!
sub delautoresponder {
    my ($email) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_auto_responder", { email => $email } );
    ## yuck: this API1 call did either a 'return' or 'return 0'
    return 0;
}

##############################
## DEFAULT ADDRESS
## DEPRECATED!
sub api2_listdefaultaddresses {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_default_address", \%CFG );
    return ( $result->data() || [] );
}

## DEPRECATED!
sub api2_setdefaultaddress {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "set_default_address", \%CFG );
    unless ( $result->status() ) {
        my $errors = $result->errors_as_string();
        return $errors if $errors;
        return ();
    }
    return ( $result->data() || [] );
}

##############################
## MAILING LISTS
## DEPRECATED!
sub api2_listlists {
    my %CFG    = ( @_, 'api.quiet' => 1, 'api2_state_key' => 'Cpanel::Email::listlists' );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_lists", \%CFG );
    return unless $result->status();
    return ( $result->data() || [] );
}

## DEPRECATED!
sub addlist {
    my ( $list, $password, $domain, $rebuildonly, $private ) = @_;

    my $result = Cpanel::API::wrap_deprecated(
        "Email",
        "add_list",
        {
            list        => $list,
            password    => $password,
            domain      => $domain,
            rebuildonly => $rebuildonly,
            private     => $private
        }
    );
    ## NOTE: used to "return" or "return 0", very inconsistently
    return;
}

## DEPRECATED!
sub passwdlist {
    my ( $list, $password ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "passwd_list", { list => $list, password => $password } );
    ## NOTE: used to "return" or "return 0", very inconsistently
    return;
}

## DEPRECATED!
sub dellist {
    my ($list) = @_;
    my $result = Cpanel::API::wrap_deprecated( 'Email', 'delete_list', { 'list' => $list, 'api.quiet' => 1 } );
    print $result->messages_as_string();
    ## NOTE: used to "return" or "return 0", very inconsistently
    return;
}

##############################
## EMAIL FILTERS
## DEPRECATED!
sub api2_filterlist {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_filters", \%OPTS );
    if ( $result->status() ) {
        return $result->data();
    }
    return;
}

## DEPRECATED!
sub api2_accountname {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( 'Email', 'account_name', \%OPTS );
    ## account_name returns a scalar
    return [ { 'account' => $result->data() } ];
}

## DEPRECATED!
sub api2_loadfilter {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_filter", \%OPTS );
    return $currentfilter = $result->data();    ## undesireable
    ## legacy version just fell through, so $currentfilter is returned
}

## DEPRECATED!
sub api2_filtername {
    return { 'filtername' => $currentfilter->{'filtername'} };
}

## DEPRECATED!
sub api2_filterrules {
    return $currentfilter->{'rules'};
}

## DEPRECATED!
sub api2_filteractions {
    return $currentfilter->{'actions'};
}

## DEPRECATED!
sub api2_reorderfilters {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "reorder_filters", \%OPTS );
    if ( $result->status() ) {
        return [ { 'ok' => 1, } ];
    }
    return;
}

## DEPRECATED!
## a particularly troubling set of return values for an API2 call
sub api2_storefilter {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "store_filter", \%OPTS );

    unless ( defined $result->data() ) {
        return;
    }

    if ( $result->status() ) {
        my $rv = [
            {
                'ok'      => 1,
                'account' => $result->data()->{'account'},
                'error'   => 0,
                'result'  => 'Filter Saved.'
            }
        ];
        return $rv;
    }

    ## ants ants
    my $rv = [
        {
            'account' => $result->data()->{'account'},
            'ok'      => 0,
            'result'  => $result->errors_as_string(),
            'error'   => 1,
        }
    ];
    return $rv;
}

##############################
sub api2_disablefilter {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "disable_filter", \%OPTS );
    return ( [ $result->data() ] );
}

sub api2_enablefilter {
    my %OPTS   = @_;
    my $result = Cpanel::API::wrap_deprecated( "Email", "enable_filter", \%OPTS );
    return ( [ $result->data() ] );
}

##############################

## DEPRECATED!
sub api2_deletefilter {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_filter", \%OPTS );

    my $data = $result->data() || {};
    ## note: delete_filter detects failure to delete filter, api2 does not
    return [
        {
            'deleted'    => 1,
            'filtername' => $data->{'filtername'}
        }
    ];
}

## DEPRECATED!
sub api2_tracefilter {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "trace_filter", \%OPTS );
    return [ $result->data() ];
}

## note: not converting; called by mailbrowser.json (the file tree
##   dropdown on the editfilter page) but the info does not seem to be used
## returns the absolute path of email dir for 'account'
sub api2_getabsbrowsedir {
    my %OPTS = @_;
    my $acct = $OPTS{'account'};
    require Cpanel::SafeDir::Fixup;
    my $rv = [ { 'absdir' => ( Cwd::abs_path( Cpanel::SafeDir::Fixup::maildirfixup( $OPTS{'dir'}, 0, 0, $acct ) ) || Cpanel::SafeDir::Fixup::maildirfixup( $OPTS{'dir'}, 0, 0, $acct ) ) } ];
    return $rv;
}

## DEPRECATED!
sub api2_browseboxes {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "browse_mailbox", \%CFG );
    unless ( $result->status() ) {
        return;
    }
    return ( $result->data || [] );
}

## DEPRECATED!
sub api2_listfilterbackups {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_filters_backups" );
    return ( $result->data() || [] );
}

##############################
## MX ENTRIES
## DEPRECATED!
sub api2_listmxs {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "list_mxs", \%CFG );
    return ( $result->data() );
}

## DEPRECATED!
sub api2_setalwaysaccept {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Email", "set_always_accept", \%OPTS );
    return unless $result->status();
    return [ $result->data() ];
}

## DEPRECATED!
sub api2_addmx {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %OPTS = ( @_, 'api.quiet' => 1 );
    $OPTS{'exchanger'} = ( $OPTS{'exchanger'} || $OPTS{'exchange'} || $OPTS{'newmx'} );
    $OPTS{'priority'}  = $OPTS{'priority'} || $OPTS{'preference'};
    my $result = Cpanel::API::wrap_deprecated( "Email", "add_mx", \%OPTS );
    return unless $result->status();
    return [ $result->data() ];
}

## DEPRECATED!
sub api2_changemx {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %OPTS = ( @_, 'api.quiet' => 1 );
    $OPTS{'exchanger'}    = ( $OPTS{'exchanger'}    || $OPTS{'exchange'} || $OPTS{'newmx'} );
    $OPTS{'priority'}     = ( $OPTS{'priority'}     || $OPTS{'preference'} );
    $OPTS{'oldexchanger'} = ( $OPTS{'oldexchanger'} || $OPTS{'oldexchange'} || $OPTS{'oldmx'} );
    $OPTS{'oldpriority'}  = ( $OPTS{'oldpriority'}  || $OPTS{'oldpreference'} );
    my $result = Cpanel::API::wrap_deprecated( "Email", "change_mx", \%OPTS );
    if ( $result->status() ) {
        return [ $result->data() ];
    }
    return;
}

## DEPRECATED!
sub api2_delmx {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %OPTS = ( @_, 'api.quiet' => 1 );
    $OPTS{'exchanger'} = ( $OPTS{'exchanger'} || $OPTS{'exchange'} || $OPTS{'newmx'} );
    $OPTS{'priority'}  = ( $OPTS{'priority'}  || $OPTS{'preference'} );
    my $result = Cpanel::API::wrap_deprecated( "Email", "delete_mx", \%OPTS );
    return unless $result->status();
    return [ $result->data() ];
}

#   Turn email signing on/off
#   Caller can only set signing for the account on which they are logged in
sub api2_set_email_signing {
    my %OPTS = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::DKIM');
    if ( !Cpanel::DKIM::mta_has_dkim() ) {
        return [ 0, 'DKIM is not enabled on this server' ];
    }

    my $arg_provided = 0;
    my @result       = (1);

    # Currently only DKIM signing is supported; others (SPF?) may be added in the future
    if ( exists $OPTS{'dkim'} ) {
        $arg_provided = 1;
        if ( $OPTS{'dkim'} =~ /^([1y]|yes|on)$/i ) {
            Cpanel::AdminBin::adminrun( 'mx', 'INSTALLDOMAINKEYS', $Cpanel::CPDATA{'DNS'}, 0 );
            push @result, 'DKIM signing enabled';
        }
        elsif ( $OPTS{'dkim'} =~ /^([0n]|no|off)$/i ) {
            Cpanel::AdminBin::adminrun( 'mx', 'UNINSTALLDOMAINKEYS', $Cpanel::CPDATA{'DNS'}, 0 );
            push @result, 'DKIM signing disabled';
        }
        else {
            $result[0] = 0;
            push @result, "Unrecognized value dkim='$OPTS{'dkim'}': use 0 or 1";
        }
    }

    if ( !$arg_provided ) {
        $result[0] = 0;
        push @result, "No 'dkim' argument provided";
    }

    return \@result;
}

#   Return the signing status of the account on which the caller is logged in
sub api2_get_email_signing {

    my %result;

    # currently on DKIM is supproted; in the future, we may also report the status of other forms of signing (SPF?)
    Cpanel::LoadModule::load_perl_module('Cpanel::DKIM');
    $result{'dkim_available'} = Cpanel::DKIM::mta_has_dkim();
    if ( $result{'dkim_available'} ) {
        $result{'dkim'} = ( -e "$Cpanel::ConfigFiles::DOMAIN_KEYS_ROOT/public/$Cpanel::CPDATA{'DNS'}" ) ? 1 : 0;
    }
    else {
        $result{'dkim'} = 0;
    }

    return %result;
}

##############################
## DEPRECATED EMAIL FILTERS SUBSYSTEM
sub api2_listfilters {
    my (@RSD);
    my %FILTERS = listfilters();

    foreach my $dest ( sort keys %FILTERS ) {
        foreach my $ele ( sort keys %{ $FILTERS{$dest} } ) {
            if ( $ele ne '' && $ele !~ /^\@/ ) {
                my $nicedest = $dest;
                if ( $nicedest eq '/dev/null' ) {
                    $nicedest = 'Discard';
                }
                push( @RSD, { 'filter' => $ele, 'dest' => $dest, 'nicedest' => $nicedest } );
            }
        }
    }
    return @RSD;
}

## DEPRECATED BY DESIGN
sub api2_get_max_email_quota {
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_max_email_quota", { 'api.quiet' => 1 } );
    $Cpanel::CPVAR{'get_max_email_quota'} = $result->data();
    return [ { 'get_max_email_quota' => $result->data() } ];
}

## DEPRECATED BY DESIGN
sub api2_get_default_email_quota {
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_default_email_quota", { 'api.quiet' => 1 } );
    $Cpanel::CPVAR{'get_default_email_quota'} = $result->data();
    return [ { 'get_default_email_quota' => $result->data() } ];
}

## DEPRECATED BY DESIGN
sub api2_get_max_email_quota_mib {
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_max_email_quota_mib", { 'api.quiet' => 1 } );
    $Cpanel::CPVAR{'get_max_email_quota_mib'} = $result->data();
    return [ { 'get_max_email_quota_mib' => $result->data() } ];
}

## DEPRECATED BY DESIGN
sub api2_get_default_email_quota_mib {
    my $result = Cpanel::API::wrap_deprecated( "Email", "get_default_email_quota_mib", { 'api.quiet' => 1 } );
    $Cpanel::CPVAR{'get_default_email_quota_mib'} = $result->data();
    return [ { 'get_default_email_quota_mib' => $result->data() } ];
}

## DEPRECATED BY DESIGN
sub api2_has_delegated_mailman_lists {
    my %OPTS = @_;

    my $delegate = $Cpanel::appname eq 'webmail' ? $Cpanel::authuser : $OPTS{'delegate'};

    require Cpanel::Mailman::Delegates;
    my ( $status, $has_delegated_mailman_lists ) = Cpanel::Mailman::Delegates::has_delegated_mailman_lists($delegate);

    $Cpanel::CPVAR{'has_delegated_mailman_lists'} = $has_delegated_mailman_lists;
    return [ { 'has_delegated_mailman_lists' => $has_delegated_mailman_lists } ];
}

sub listfilters {
    my %filters;

    open( my $filter_handle, '<', "$Cpanel::homedir/.filter" ) or return ();

    # Create once per call rather than once per line
    my $line;
    while ( $line = <$filter_handle> ) {
        chomp($line);
        if ( $line ne '' ) {
            my ( $fl, $dest ) = split( /[+]{7}/, $line );
            if ( $dest eq '' ) {
                $dest = '/dev/null';
            }
            $filters{$dest}{$fl} = 1;
        }
    }
    close $filter_handle;
    return %filters;
}

# we need to wrap _listlists as it can be used in other location
sub listlists {
    my @list = Cpanel::API::Email::_listlists(@_);

    # try...catch
    return if @list && !defined $list[0];
    return @list;
}

## deprecated API1 call
sub tracefilter {
    my ( $tracefile, $msg ) = @_;

    #We get $tracefile from cpanel.pl, which does no validation
    #on the domain name. So let’s do that validation here since
    #there are other callers into this logic.

    #API1 requires a domain name rather than an account name.
    $tracefile =~ m<\A\Q$Cpanel::ConfigFiles::VFILTERS_DIR\E/(.*)> or do {
        die "Invalid tracefile: [$tracefile]\n";
    };

    if ( !length $1 ) {
        die "Submit a domain name.\n";
    }

    require Cpanel::Validate::Domain;
    Cpanel::Validate::Domain::valid_rfc_domainname_or_die($1);

    my ( $rv, $reason ) = Cpanel::API::Email::_tracefilter( $tracefile, $msg );
    if ( !main::hasfeature("blockers") ) { return (); }
    if ($rv) {
        return $reason;
    }
    else {
        print $reason;
        return;
    }

}

##############################
## utility functions whose original versions used to print directly to screen;
##   as such, their return signatures have changed enough to merit two versions
##   instead of just aliasing into Cpanel::API::Email

## previously returned undef, or a list of destinations (strings)
sub _buildfwd {
    my ( $dests_ref, $errors_ref ) = Cpanel::API::Email::_buildfwd(@_);
    if ( defined $errors_ref && ref($errors_ref) eq 'ARRAY' ) {
        print "$_<br /><br />" for @$errors_ref;
    }
    return ref($dests_ref) eq 'ARRAY' ? @$dests_ref : undef;
}

## previously returned $Cpanel::user, '', or a comma-delimited list of @EMAILS; printed
##   errors directly to screen
sub _resolveemails {
    my ( $email, $errors_ref ) = Cpanel::API::Email::_resolveemails(@_);
    if ( defined $errors_ref && ref($errors_ref) eq 'ARRAY' ) {
        print "$_<br /><br />" for @$errors_ref;
    }
    return $email;
}

## previously returned a list: boolean, and an error string; potentially printed errors,
##   depending on $quiet
sub quotatest {
    my $quiet = shift;
    my ( $rv, $msg ) = Cpanel::API::Email::_quotatest();
    unless ($rv) {
        $Cpanel::CPERROR{'email'} = $msg;
        if ($quiet) {
            return 0, $msg;
        }
        print $msg;
        return 0;
    }
    return 1;
}

## previously returned boolean (inconsistenly), and printed errors
sub rebuildconf {
    my ($aliases_obj) = @_;

    try {
        $aliases_obj->save();
    }
    catch {
        print qq(<br />\n<font color="#FF0000">);
        map { print "$_<br />\n" } Cpanel::Exception::get_string($_);
        print qq(</font><br />\n);
    };

    return;
}

## previously returned list: (boolean, and array-ref of addresses)
sub _resolve_alias_to_addys {
    my $email  = shift;
    my $nowarn = shift;
    my ( $status, $addys, $errors ) = Cpanel::API::Email::_resolve_alias_to_addys( $email, $nowarn );
    if ( defined $errors and ref($errors) eq 'ARRAY' ) {
        print $_ for @$errors;
    }
    return ( $status, $addys );
}

sub defaultaddress {
    my ($domain) = @_;
    my ( $address, $errors ) = Cpanel::API::Email::_defaultaddress($domain);
    if ( defined $errors and ref($errors) eq 'ARRAY' ) {
        print qq(<br />\n<font color="#FF0000">);
        print "$_<br />\n" for @$errors;
        print qq(</font><br />\n);
    }
    return $address;
}

## previously returned boolean false or a hash (which was always ignored)
sub get_mailconfig {
    my $domain = shift;

    my ( $conf, $conf_errors ) = Cpanel::API::Email::_get_mailconfig($domain);

    ## assignment of $conf_errors to CPERROR happens in ::API:: version
    ## ...but just in case:
    $Cpanel::CPERROR{'email'} ||= $conf_errors;

    return $conf;
}

sub _managepopdbs {
    my %OPTS = @_;
    my ( $data, $error ) = Cpanel::Email::Accounts::manage_email_accounts_db(%OPTS);
    if ( defined $error ) {
        $Cpanel::CPERROR{'email'} = $error;
    }
    return $data;
}

sub _get_addpop_result {
    my ($dataref) = @_;
    return $dataref->[0]{result};
}

sub _filestorage_is_on() {
    require Cpanel::Server::Type::Role::FileStorage;
    return Cpanel::Server::Type::Role::FileStorage->is_enabled();
}

my $send_and_receive_mail = { match => 'all', roles => [ 'MailSend', 'MailReceive' ] };

my $mail_send_and_receive_roles_allow_demo = {
    worker_node_type => 'Mail',
    needs_role       => $send_and_receive_mail,
    allow_demo       => 1,
};

my $mail_receive_role_allow_demo = {
    worker_node_type => 'Mail',
    needs_role       => "MailReceive",
    allow_demo       => 1,
};

my $dns_role_changemx_feature = {
    needs_role    => "DNS",
    needs_feature => "checkmx",
};

my $mail_receive_role_blockers_feature = {
    worker_node_type => 'Mail',
    needs_role       => "MailReceive",
    needs_feature    => "blockers",
};

my $mail_receive_role_emailarchive_feature = {
    worker_node_type => 'Mail',
    needs_role       => "MailReceive",
    needs_feature    => "emailarchive",
};

my $mail_receive_role_emailarchive_feature_allow_demo = {
    worker_node_type => 'Mail',
    needs_role       => "MailReceive",
    needs_feature    => "emailarchive",
    allow_demo       => 1,
};

my $mail_receive_role_popaccts_feature = {
    worker_node_type => 'Mail',
    needs_role       => "MailReceive",
    needs_feature    => "popaccts",
};

my $xss_checked_modify_none_mail_receive_role_blockers_feature = {
    worker_node_type => 'Mail',
    'xss_checked'    => 1,
    'modify'         => 'none',
    needs_role       => "MailReceive",
    needs_feature    => "blockers",
    allow_demo       => 1,
};

our %API = (

    # mailing lists need send & receive
    'listlists'                   => $mail_send_and_receive_roles_allow_demo,    # Wrapped Cpanel::API::Email::list_lists
    'has_delegated_mailman_lists' => {
        worker_node_type => 'Mail',
        needs_role       => $send_and_receive_mail,
        needs_feature    => "lists",
        allow_demo       => 1,
    },

    # forwarders need send & receive
    'adddomainforward' => {                                                      # Wrapped Cpanel::API::Email::add_domain_forwarder
        worker_node_type => 'Mail',
        needs_role       => $send_and_receive_mail,
        needs_feature    => "emaildomainfwd",
        allow_demo       => 1,
    },
    'listforwards'       => $mail_send_and_receive_roles_allow_demo,             # Wrapped Cpanel::API::Email::list_forwarders
    'listdomainforwards' => $mail_send_and_receive_roles_allow_demo,             # Wrapped Cpanel::API::Email::list_domain_forwarders
    'addforward'         => {                                                    # Wrapped Cpanel::API::Email::add_forwarder
        worker_node_type => 'Mail',
        'xss_checked'    => 1,
        'modify'         => 'none',
        needs_role       => $send_and_receive_mail,
        needs_feature    => "forwarders",
        allow_demo       => 1,
    },
    'delforward' => {                                                            # Wrapped Cpanel::API::Email::delete_forwarder
        worker_node_type => 'Mail',
        needs_role       => $send_and_receive_mail,
        needs_feature    => "forwarders",
        allow_demo       => 1,
    },

    # auto-responders need send & receive
    'fetchautoresponder' => $mail_send_and_receive_roles_allow_demo,             # Wrapped Cpanel::API::Email::get_auto_responder
    'listautoresponders' => $mail_send_and_receive_roles_allow_demo,             # Wrapped Cpanel::API::Email::list_auto_responders

    # MX records require DNS (not mail at all!)
    'addmx'      => $dns_role_changemx_feature,                                  # Wrapped Cpanel::API::Email::add_mx
    'changemx'   => $dns_role_changemx_feature,                                  # Wrapped Cpanel::API::Email::change_mx
    'delmx'      => $dns_role_changemx_feature,                                  # Wrapped Cpanel::API::Email::delete_mx
    'setmxcheck' => {                                                            # Wrapped Cpanel::API::Email::set_always_accept (via api2_setalwaysaccept)
        'func'        => 'api2_setalwaysaccept',
        needs_role    => 'DNS',
        needs_feature => "changemx",
    },
    'setalwaysaccept' => $dns_role_changemx_feature,                             # Wrapped Cpanel::API::Email::set_always_accept
    'getmxcheck'      => {
        'func'        => 'api2_getalwaysaccept',
        needs_role    => 'DNS',
        needs_feature => "changemx",
        allow_demo    => 1,
    },
    'getalwaysaccept' => $dns_role_changemx_feature,
    'listmx'          => {                                                       # Wrapped Cpanel::API::Email::list_mxs
        'func'     => 'api2_listmxs',
        needs_role => 'DNS',
        allow_demo => 1,
    },
    'listmxs' => { needs_role => 'DNS', allow_demo => 1 },                       # Wrapped Cpanel::API::Email::list_mxs

    # Everything else just needs MailReceive, which we’ll
    # set at the bottom.

    'listpopssingle'              => $mail_receive_role_allow_demo,                        # Wrapped Cpanel::API::Email::list_pops (via api2_listpops)
    'loadfilter'                  => $mail_receive_role_blockers_feature,                  # Wrapped Cpanel::API::Email::get_filter
    'listmaildomains'             => $mail_receive_role_allow_demo,                        # Wrapped Cpanel::API::Email::list_mail_domains
    'accountname'                 => $mail_receive_role_allow_demo,                        # Wrapped Cpanel::API::Email::account_name
    'filtername'                  => $mail_receive_role_allow_demo,
    'listpops'                    => $mail_receive_role_allow_demo,                        # Wrapped Cpanel::API::Email::list_pops
    'get_archiving_types'         => $mail_receive_role_emailarchive_feature_allow_demo,
    'get_archiving_configuration' => {
        worker_node_type => 'Mail',
        'sort_methods'   => {
            'diskused' => 'numeric',
        },
        'postfunc'    => \&api2post_get_archiving_configuration,
        needs_role    => "MailReceive",
        needs_feature => "emailarchive",
        allow_demo    => 1,
    },
    'set_archiving_configuration'         => $mail_receive_role_emailarchive_feature,
    'set_archiving_default_configuration' => $mail_receive_role_emailarchive_feature_allow_demo,
    'get_archiving_default_configuration' => $mail_receive_role_emailarchive_feature_allow_demo,
    'browseboxes'                         => {                                                     # Wrapped Cpanel::API::Email::browse_mailbox
        worker_node_type => 'Mail',
        'xss_checked'    => 1,
        'modify'         => 'none',
        needs_role       => "MailReceive",
        allow_demo       => 1,
    },
    'setdefaultaddress' => {                                                                       # Wrapped Cpanel::API::Email::set_default_address
        worker_node_type => 'Mail',
        'xss_checked'    => 1,
        'modify'         => 'none',
        needs_role       => "MailReceive",
        needs_feature    => "defaultaddress",
        allow_demo       => 1,
    },
    'storefilter'          => $xss_checked_modify_none_mail_receive_role_blockers_feature,         # Wrapped Cpanel::API::Email::store_filter
    'checkmaindiscard'     => $mail_receive_role_allow_demo,
    'filteractions'        => $mail_receive_role_allow_demo,
    'listdefaultaddresses' => $mail_send_and_receive_roles_allow_demo,                             # Wrapped Cpanel::API::Email::list_default_address
    'fetchcharmaps'        => $mail_receive_role_allow_demo,                                       # Wrapped Cpanel::API::Email::fetch_charmaps
    'clearpopcache'        => $mail_receive_role_allow_demo,
    'deletefilter'         => $xss_checked_modify_none_mail_receive_role_blockers_feature,         # Wrapped Cpanel::API::Email::delete_filter
    'disablefilter'        => $mail_receive_role_blockers_feature,                                 # Wrapped Cpanel::API::Email::disable_filter
    'enablefilter'         => $mail_receive_role_blockers_feature,                                 # Wrapped Cpanel::API::Email::enable_filter
    'getabsbrowsedir'      => {
        worker_node_type => 'Mail',
        'xss_checked'    => 1,
        'modify'         => 'none',
        needs_role       => "MailReceive",
        allow_demo       => 1,
    },
    'filterrules'       => $mail_receive_role_allow_demo,
    'getdiskusage'      => $mail_receive_role_allow_demo,                                          # Wrapped Cpanel::API::Email::get_disk_usage
    'listfilterbackups' => $mail_receive_role_blockers_feature,                                    # Wrapped Cpanel::API::Email::list_filters_backup
    'filterlist'        => $mail_receive_role_blockers_feature,                                    # Wrapped Cpanel::API::Email::list_filters
    'listpopswithdisk'  => {                                                                       # Wrapped Cpanel::API::Email::list_pops_with_disk
        worker_node_type => 'Mail',
        'csssafe'        => 1,
        needs_role       => "MailReceive",
        allow_demo       => 1,
    },
    'tracefilter' => {                                                                             # Wrapped Cpanel::API::Email::trace_filter
        worker_node_type => 'Mail',
        'csssafe'        => 1,
        'xss_checked'    => 1,
        'modify'         => 'none',
        needs_role       => "MailReceive",
        needs_feature    => "blockers",
        allow_demo       => 1,
    },
    'listaliasbackups'  => $mail_send_and_receive_roles_allow_demo,                                # Wrapped Cpanel::API::Email::list_forwarder_backups
    'listfilters'       => $mail_receive_role_allow_demo,
    'reorderfilters'    => $mail_receive_role_blockers_feature,                                    # Wrapped Cpanel::API::Email::reorder_filters
    'listpopswithimage' => $mail_receive_role_allow_demo,                                          # Wrapped Cpanel::API::Email::list_pops (via api2_listpops)
    'addpop'            => {                                                                       # Wrapped Cpanel::API::Email::add_pop

        # addpop weirdly stores its result and reason inside of the data section, so
        # we have to provide this special hint to grab it from there instead of from
        # the regular API metadata when gathering addpop analytics data.
        analytics => {
            verb       => 'CREATE',
            noun       => 'EMAIL_ACCOUNT',
            get_result => \&_get_addpop_result,
        },
        needs_role       => "MailReceive",
        needs_feature    => "popaccts",
        worker_node_type => 'Mail',
    },
    'delpop'                      => $mail_receive_role_popaccts_feature,    # Wrapped Cpanel::API::Email::delete_pop
    'editquota'                   => { needs_role => 'MailReceive' },        # Wrapped Cpanel::API::Email::edit_pop_quota
    'passwdpop'                   => $mail_receive_role_popaccts_feature,    # Wrapped Cpanel::API::Email::passwd_pop
    'list_system_filter_info'     => $mail_receive_role_blockers_feature,    # Wrapped Cpanel::API::Email::list_system_filter_info
    'set_email_signing'           => $mail_receive_role_allow_demo,
    'get_email_signing'           => $mail_receive_role_allow_demo,
    'get_max_email_quota'         => $mail_receive_role_allow_demo,          # Wrapped Cpanel::API::Email::get_max_email_quota
    'get_default_email_quota'     => $mail_receive_role_allow_demo,          # Wrapped Cpanel::API::Email::get_default_email_quota
    'get_max_email_quota_mib'     => $mail_receive_role_allow_demo,          # Wrapped Cpanel::API::Email::get_max_email_quota_mib
    'get_default_email_quota_mib' => $mail_receive_role_allow_demo,          # Wrapped Cpanel::API::Email::get_default_email_quota_mib
);

##############################
sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
