package Cpanel::HttpUtils::Htaccess;

# cpanel - Cpanel/HttpUtils/Htaccess.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::ApacheConf::Check ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

use Cpanel::Finally                      ();
use Cpanel::LoadModule                   ();
use Cpanel::Debug                        ();
use Cpanel::StringFunc::UnquoteMeta      ();
use Cpanel::UTF8::Utils                  ();
use Cpanel::DomainLookup                 ();
use Cpanel::Encoder::Tiny                ();
use Cpanel::Encoder::URI                 ();
use Cpanel::Exception                    ();
use Cpanel::Transaction::File::Raw       ();              # PPI USE OK - dynamic load below
use Cpanel::Transaction::File::RawReader ();              # PPI USE OK - dynamic load below
use Cpanel::Rand::Get                    ();
use Cpanel::HttpUtils::Version           ();
use Cpanel::OrDie                        ();
use Cpanel::Regex                        ();
use Cpanel::Imports;
use bytes;                                                # Case 15186: TODO define why 'bytes' is important here

=head1 MODULE

C<Cpanel::HttpUtils::Htaccess>

=head1 DESCRIPTION

C<Cpanel::HttpUtils::Htaccess> provides access to .htaccess files.

Note: .htaccess files are under user control and users will add and remove
content from them for various customization they want for their web server.
When we make changes to these files use the C<append_section_header> and
C<append_section_footer> to wrap features we control in cpanel comment
blocks so uses know not to mess with those sections.

Important: these routines are not compatible with <files> or similar directives
that support nesting of directives in an .htaccess file.

=cut

our $VERSION = 1.0;

=head1 STATIC PROPERTIES

=head2 MODES

Hash of the modes supported by open method.

=head3 OPTIONS

=over

=item READONLY

Open the passwd file as read-only

=item READWRITE

Open the passwd file as read-write

=back

=cut

our %MODES = (
    READONLY  => 'Cpanel::Transaction::File::RawReader',
    READWRITE => 'Cpanel::Transaction::File::Raw',
);

my $HTACCESS_PERMS = 0644;

our ( $rewrite_cache_changed, $rewrite_cache_loaded, $rewrite_cache_ref ) = ( 0, 0, {} );

=head2 append_section_header(TAG, NAME, LINES)

Appends a comment header to the .htaccess file. It looks something like the following:

  #--------------------------------------------------------------cp:ppd
  # Section managed by cPanel: Password Protected Directory     -cp:ppd
  # - Do not edit this section of the htaccess file!            -cp:ppd
  #--------------------------------------------------------------cp:ppd
  ...
  #--------------------------------------------------------------cp:ppd
  # End section managed by cPanel: Password Protected Directory -cp:ppd
  #--------------------------------------------------------------cp:ppd

=head3 ARGUMENTS

=over

=item TAG - string

Short name for the feature used in the comment line trailer.

=item NAME - string

Long name for the feature used in the description comment block.

=item LINES - string[]

Reference to array of .htaccess file line already written.

=back

=cut

sub append_section_header {
    my ( $section_tag, $section_name, $htaccess_ref ) = @_;
    my $DIVIDER = '-' x 63;
    push @$htaccess_ref, "#$DIVIDER-cp:$section_tag";
    push @$htaccess_ref, "# Section managed by cPanel: $section_name     -cp:$section_tag";
    push @$htaccess_ref, "# - Do not edit this section of the htaccess file!              -cp:$section_tag";
    push @$htaccess_ref, "#$DIVIDER-cp:$section_tag";
    return;
}

=head2 append_section_footer(TAG, NAME, LINES)

Appends a comment header to the .htaccess file. It looks something like the following:

  ...
  #--------------------------------------------------------------cp:ppd
  # End section managed by cPanel: Password Protected Directory -cp:ppd
  #--------------------------------------------------------------cp:ppd

=head3 ARGUMENTS

=over

=item TAG - string

Short name for the feature used in the comment line trailer.

=item NAME - string

Long name for the feature used in the description comment block.

=item LINES - string[]

Reference to array of .htaccess file line already written.

=back

=cut

sub append_section_footer {
    my ( $section_tag, $section_name, $htaccess_ref ) = @_;
    my $DIVIDER = '-' x 63;
    push @$htaccess_ref, "#$DIVIDER-cp:$section_tag";
    push @$htaccess_ref, "# End section managed by cPanel: $section_name -cp:$section_tag";
    push @$htaccess_ref, "#$DIVIDER-cp:$section_tag";
    return;
}

=head2 update_protected_directives(DOCROOT, INFO)

Update a limited set of fields for existing password protected directory
settings. This is used by the _upgrade_passwd_file_location helper in
C<Cpanel::Htaccess> only.

=cut

sub update_protected_directives {
    my ( $docroot, $info ) = @_;

    my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open( $docroot, $MODES{READWRITE} );

    my @htaccess     = split( m{\n}, ${ $htaccess_trans->get_data() } );
    my $is_protected = 0;

    for my $index ( 0 .. $#htaccess ) {
        if ( $htaccess[$index] =~ m{^\s*AuthName\s+}i && defined $info->{auth_name} ) {
            $htaccess[$index] = "AuthName " . _quoted( $info->{auth_name} );
        }

        if ( $htaccess[$index] =~ /^\s*AuthUserFile\s+/i && defined $info->{passwd_file} ) {
            $htaccess[$index] = "AuthUserFile " . _quoted( $info->{passwd_file} );
        }

        if ( $htaccess[$index] =~ /^\s*Require valid-user/i ) {
            $is_protected = 1;
        }
    }

    $htaccess_trans->set_data( \join( "\n", @htaccess ) );

    my ( $status, $msg ) = test_and_install_htaccess(
        installdir     => $docroot,
        htaccess_trans => $htaccess_trans,
    );

    die $msg if !$status;
    return {
        auth_type   => $is_protected ? 'Basic' : undef,
        auth_name   => $info->{auth_name},
        passwd_file => $info->{passwd_file},
        protected   => $is_protected,
    };
}

=head2 set_protected_directives(DOCROOT, INFO)

Creates or updates the entire password protected directory directive set
based on what is passed in the INFO hash.

=head3 ARGUMENTS

=over

=item DOCROOT - string

=item INFO - hashref

=over

=item protected - Boolean

Will enable protection when 1, or disable protection when 0.

=item auth_name - string

Name to set for the protected resource.

=item passwd_file - string

Full path to the password file to use for the user database.

=back

=back

=head3 RETURNS

Hashref with the following properties:

=over

=item auth_type - string

Type of authentication. Currently will only be: Basic or undef

=item auth_name - string

Name used for the resource when protection is enabled

=item passwd_file - string

Path to the password file on disk when protection is enabled

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=head3 LIMITATIONS

Not compatible with <files> directives or any other directives that can have nested directives.

=cut

sub set_protected_directives {
    my ( $docroot, $info ) = @_;

    my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open( $docroot, $MODES{READWRITE} );

    my @htaccess;

    my $TAG      = 'ppd';
    my $APP_NAME = 'Password Protected Directories';

    # Remove any previous password protected directory directives
    foreach my $line ( split( m{\n}, ${ $htaccess_trans->get_data() } ) ) {
        if (   $line =~ m/^\s*AuthType/i
            || $line =~ m/^\s*AuthName\s+"?((?:[^"\\\n]|\\.)*)"?/i
            || $line =~ m/^\s*AuthUserFile\s+"?((?:[^"\\\n]|\\.)*)"?/i
            || $line =~ m/^\s*Require valid-user/i
            || $line =~ m/^#.*-cp:\Q$TAG\E$/ ) {
            next;
        }
        else {
            push @htaccess, $line;
        }
    }

    # Add password protected directory directives
    if ( $info->{protected} ) {
        push @htaccess, "";
        append_section_header( $TAG, $APP_NAME, \@htaccess );
        push @htaccess, 'AuthType Basic';
        push @htaccess, "AuthName " . _quoted( $info->{auth_name} );
        push @htaccess, "AuthUserFile " . _quoted( $info->{passwd_file} );
        push @htaccess, 'Require valid-user';
        append_section_footer( $TAG, $APP_NAME, \@htaccess );
    }

    $htaccess_trans->set_data( \join( "\n", @htaccess ) );

    my ( $status, $msg ) = test_and_install_htaccess(
        installdir     => $docroot,
        htaccess_trans => $htaccess_trans,
    );

    die $msg if !$status;

    # Return the new state
    return {
        auth_type   => $info->{protected} ? 'Basic' : undef,
        auth_name   => $info->{auth_name},
        passwd_file => $info->{passwd_file},
        protected   => $info->{protected},
    };
}

=head2 get_protected_directives(DOCROOT)

Gets the protected directive values for the document root.

=head3 ARGUMENTS

=over

=item DOCROOT - string

Full path to the directory you want a list of users for.

=back

=head3 RETURNS

Hashref with the following properties:

=over

=item auth_type - string

Type of authentication. Currently will only be: Basic

=item auth_name - string

Name used for the resource

=item passwd_file - string

Path to the password file on disk

=item protected - Boolean

1 if protected, 0 if not protected.

=back

=head3 LIMITATIONS

Not compatible with <files> directives or any other directives that can have nested directives.

=cut

sub get_protected_directives {
    my ($docroot) = @_;

    my $htaccess_trans = Cpanel::HttpUtils::Htaccess::open( $docroot, $MODES{READONLY} );

    my ( $auth_type, $auth_name, $passwd_file, $protected ) = ( 'None', '', '', 0 );
    foreach my $line ( split( m{\n}, ${ $htaccess_trans->get_data() } || '' ) ) {
        if ( $line =~ m/^\s*AuthType\s+"?([^"\s]+)/i ) {
            $auth_type = $1;
        }
        elsif ( $line =~ m/^\s*AuthName\s+"?((?:[^"\\\n]|\\.)*)/i ) {

            # See: https://regex101.com/r/DWT00x/1/ for testing
            $auth_name = $1;
            $auth_name =~ s{\\(.)}{$1};    # clean up escaped characters
        }
        elsif ( $line =~ m/^\s*AuthUserFile\s+"?((?:[^"\\\n]|\\.)*)/i ) {

            # See: https://regex101.com/r/gf1LTv/2 for testing
            $passwd_file = $1;
            $passwd_file =~ s{\\(.)}{$1};    # clean up escaped characters
        }
        elsif ( $line =~ m/^\s*Require\s+valid-user/i ) {
            $protected = 1;
        }
    }

    return {
        auth_type   => $auth_type,
        auth_name   => _unescape($auth_name),
        passwd_file => $passwd_file,
        protected   => $protected,
    };
}

sub getrewriteinfo {
    my ( $docroot, $domain, $now ) = @_;
    my ( $nexturl, $url );
    my ( $size,    $mtime ) = ( stat( $docroot . '/.htaccess' ) )[ 7, 9 ];

    if ( !$size ) { return ( 'not redirected', '', 0 ); }

    if ( exists $rewrite_cache_ref->{$docroot}{$domain} && $rewrite_cache_ref->{$docroot}{$domain}->{'mtime'} > $mtime && $rewrite_cache_ref->{$docroot}{$domain}->{'mtime'} < ( $now || time() ) ) {
        $Cpanel::Debug::level >= 5 && print STDERR "getrewriteinfo: Using Cache for $docroot [$domain]\n";
        return ( $rewrite_cache_ref->{$docroot}{$domain}->{'status'}, $rewrite_cache_ref->{$docroot}{$domain}->{'url'}, defined $rewrite_cache_ref->{$docroot}{$domain}->{'url'} ? 1 : 0 );
    }
    $Cpanel::Debug::level >= 5 && print STDERR "getrewriteinfo: Not Using Cache for $docroot [$domain] Test Failed: ($rewrite_cache_ref->{$docroot}{$domain}->{'mtime'} > $mtime) \n";

    my $quoted_domain = Cpanel::UTF8::Utils::quotemeta($domain);

    local $@;
    my $htaccess_trans = eval { open_htaccess_ro($docroot) };

    if ( !$htaccess_trans || $@ ) {
        Cpanel::Debug::log_warn($@) if $@;
        return ( 'unknown', '', 0 );
    }

    foreach ( split( m{\n}, ${ $htaccess_trans->get_data() } ) ) {
        if (   m/^\s*RewriteCond/i
            && m/HTTP_HOST/
            && ( m/\^\Q${domain}\E\$/i || m/\^www\.\Q${domain}\E\$/i || m/\^\Q${quoted_domain}\E\$/i || m/\^\Qwww\.${quoted_domain}\E\$/i ) ) {
            $nexturl = 1;
        }
        if ( $nexturl && ( m/^\s*RewriteRule\s+\S+\s+["]((?:\\"|[^"])+)["]/i || m/^\s*RewriteRule\s+\S+\s+(\S+)/i ) ) {
            $url = $1;
            $url =~ s{^["]+|["]+$}{}g;
            $url     = Cpanel::StringFunc::UnquoteMeta::unquotemeta($url);
            $nexturl = 0;
        }
    }
    my $status = defined $url ? $url : 'not redirected';

    # The $status field is used to generate links in various interfaces.
    # When not using a absolute URL, we should append the domain.
    # See Case 118121 for further information.

    if ($url) {
        if ( $url !~ m{^((https?|ftp)://)} ) {
            my $s_url = $url;
            $s_url =~ s{^/}{};    # Extra /'s
            $status = 'http://' . $domain . '/' . $s_url;
        }
    }

    $rewrite_cache_changed = 1;
    $rewrite_cache_ref->{$docroot}{$domain} = { 'status' => $status, 'url' => $url, 'mtime' => ( time() - 1 ) };

    return ( $status, $url, defined $url ? 1 : 0 );
}

sub getredirects {    ## no critic (Subroutines::ProhibitExcessComplexity) -- Can't refactor this in a bug fix.
    my $nexturl     = 0;
    my $docrootonly = shift;    #only look in a specific doc root if an argument is passed
    my $user        = shift;    #optional; only look up the user in question.
    my $domain;
    my $haswww = 0;
    my @RSD;
    my $docrootslist_ref = Cpanel::DomainLookup::getdocrootlist($user);
    foreach my $docroot ( keys %{$docrootslist_ref} ) {
        if ( $docrootonly && $docroot ne $docrootonly ) { next(); }
        my $htaccess_trans;
        try {
            $htaccess_trans = open_htaccess_ro($docroot);
        };

        #
        # The try is lacking a catch because
        # the system will already warns in the log if something
        # fails.  Since we are listing redirects we want to
        # move on to the next .htaccess file in the event
        # something is wrong.  If there is a more sinister problem
        # the user will see the error in the UI
        # when they modify a redirect for the document root.
        # This preserves existing behavior.
        #
        # XXX: … however, the only report of these failures to the caller
        # directly is via $Cpanel::CPERROR{$Cpanel::context}, which means
        # that if there are multiple failures, then only the last failure
        # will be reported to the caller.

        next if !$htaccess_trans;
        my $data_ref = $htaccess_trans->get_data();
        next if !length $$data_ref;    # may not have any
        foreach ( split( m{\n}, $$data_ref ) ) {
            if (   m/^\s*RewriteCond/i
                && m/HTTP_HOST/
                && m/\^(www\\?\.)?([^\$]+)\$/i ) {
                $domain  = Cpanel::StringFunc::UnquoteMeta::unquotemeta($2);
                $nexturl = 1;
                if ( m/\s+\^www\\?\./ || m/\s+\Q^(.*)\E/ || m/\s+\^\.\*\$/ ) {
                    $haswww = 1;
                }
            }
            elsif ( $nexturl && !m/P\,QSA\,L\]\s*$/ && ( m/^\s*RewriteRule\s+((?:\S|\\ )+)\s+["]((?:\\"|[^"])+)["]\s*(\S*)/i || m/^\s*RewriteRule\s+((?:\S|\\ )+)\s+(\S+)\s*(\S*)/i ) ) {
                $nexturl = 0;
                my $sourceurl = $1;
                my $targeturl = $2;
                $sourceurl = Cpanel::StringFunc::UnquoteMeta::unquotemeta($sourceurl);
                $targeturl =~ s{^["]+|["]+$}{}g;
                $targeturl = Cpanel::StringFunc::UnquoteMeta::unquotemeta($targeturl);
                my $rinfo    = $3;
                my $wildcard = 0;

                if ( $targeturl =~ m/(\%\{REQUEST_URI\}|\$1)$/ ) {
                    $targeturl =~ s/(\%\{REQUEST_URI\}|\$1)$//g;
                    $wildcard = 1;
                }
                $sourceurl =~ s/^\^|(?:\/\?)?\(?\.\*\)?\$$|(?:\/\?)?\$$//g;
                if ( $sourceurl !~ /^\// ) { $sourceurl = '/' . $sourceurl; }
                $rinfo =~ s/R=(\d+),?//;
                my $type = $1;
                $rinfo =~ s/^.*\[([^\]]+)\].*$/$1/;
                push @RSD,
                  {
                    'docroot'    => $docroot,
                    'matchwww'   => $haswww,
                    'wildcard'   => $wildcard,
                    'kind'       => 'rewrite',
                    'domain'     => $domain,
                    'sourceurl'  => $sourceurl,
                    'targeturl'  => $targeturl,
                    'type'       => redirect_type($type),
                    'opts'       => $rinfo,
                    'statuscode' => $type
                  };
                $haswww = 0;
            }
            elsif (m/^\s*redirect(match)?\s+(.*)$/i) {
                my $match      = $1 || '';
                my $arg_string = $2;
                my @args;
                while (
                    $arg_string =~ m/
                                ((?:$Cpanel::Regex::regex{'doublequotedstring'})
                                |
                                (?:$Cpanel::Regex::regex{'singlequotedstring'})
                                |
                                \S+) # no quotes
                                /xg
                ) {
                    push( @args, $1 );
                }

                my $sourceurl;
                my $targeturl;
                my $type;
                my $statuscode;
                my $wildcard = 0;

                #check for an optional numerical status code
                if ( $args[0] =~ /^\d+$/ ) {
                    $type       = 'permanent';
                    $statuscode = $args[0];
                    $sourceurl  = $args[1];
                    $targeturl  = $args[2] if $args[2];    # target URL is not required in all cases.
                }
                elsif ( $args[2] ) {
                    $type      = $args[0];
                    $sourceurl = $args[1];
                    $targeturl = $args[2];
                }
                else {
                    $type      = 'permanent';
                    $sourceurl = $args[0];
                    $targeturl = $args[1];
                }

                $statuscode = $type =~ m/(?:perm)/i ? 301 : 302 if !$statuscode;

                # do not strip the ^ and $ if this is a regex match.
                $sourceurl =~ s/^\^//g if !$match;
                $sourceurl =~ s/\$$//g if !$match;
                if ( defined $targeturl && $targeturl =~ m/(\%\{REQUEST_URI\}|\$1)$/ ) {
                    $targeturl =~ s/(\%\{REQUEST_URI\}|\$1)$//g;
                    $wildcard = 1;
                }

                push @RSD,
                  {
                    'docroot'    => $docroot,
                    'kind'       => 'redirect' . $match,
                    'wildcard'   => $wildcard,
                    'domain'     => '.*',
                    'sourceurl'  => $sourceurl,
                    'targeturl'  => $targeturl,
                    'type'       => redirect_type($type),
                    'statuscode' => $statuscode,
                    'arguments'  => $arg_string
                  };
            }
        }
    }
    return @RSD;
}

#Ensures that the .htaccess has RewriteOptions and RewriteEngine.
sub setup_rewrite {
    my $docroot    = shift;
    my $htaccess   = $docroot . '/.htaccess';
    my $hasrengine = 0;
    my $hasropts   = 0;

    if ( !-e $docroot ) {
        mkdir( $docroot, 0755 );
    }

    my ( $htaccess_trans, $exception );
    try {
        $htaccess_trans = open_htaccess_rw($docroot);
    }
    catch {
        $exception = $_;
    };

    if ($exception) {
        return ( 0, Cpanel::Exception::get_string_no_id($exception) );
    }

    my @htaccess;
    foreach ( split( m{\n}, ${ $htaccess_trans->get_data() } ) ) {
        if (/^[\s\t]*RewriteOptions inherit/i) {
            $hasropts = 1;
        }
        elsif (/^[\s\t]*RewriteEngine on/i) {
            $hasrengine = 1;
        }
        push @htaccess, "$_\n";
    }

    if ( !$hasropts ) {
        unshift @htaccess, "\nRewriteOptions inherit\n";
    }
    if ( !$hasrengine ) {
        unshift @htaccess, "\nRewriteEngine on\n";
    }
    $htaccess_trans->set_data( \join( '', @htaccess ) );

    my ( $status, $msg ) = test_and_install_htaccess(
        'installdir'     => $docroot,
        'htaccess_trans' => $htaccess_trans,
    );

    return ( $status, $msg );
}

sub _get_redirect_exclusions {
    Cpanel::LoadModule::load_perl_module('Cpanel::ApacheConf::DCV');
    BEGIN { ${^WARNING_BITS} = ''; }    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- cheap no warnings
    *_get_redirect_exclusions = \&Cpanel::ApacheConf::DCV::get_patterns;
    goto \&Cpanel::ApacheConf::DCV::get_patterns;
}

sub _normalize_htaccess_lines {
    my ( $trans, $domain_to_remove ) = @_;

    my $quoted_domain_to_remove = $domain_to_remove && Cpanel::UTF8::Utils::quotemeta($domain_to_remove);

    #lookup hash; “refill” this every time we begin
    #a new rewrite block.
    my %cur_rewrite_missing_dcv_exclusions;

    my $skip_cur_rewrite = 0;

    my $hasrengine;

    my @HTACCESS;

    my $added = 0;

    my @lines = split( m{\n}, ${ $trans->get_data() } );

    Cpanel::LoadModule::load_perl_module('Cpanel::ApacheConf::ModRewrite::RewriteCond');
  LINE:
    foreach my $line (@lines) {

        if ( $line =~ /^[\s\t]*RewriteCond/i ) {

            my $cond;

            #Don’t bother warn()ing on an unparsable value because it could
            #be one of the variants of RewriteCond that we don’t parse.
            try {
                $cond = Cpanel::ApacheConf::ModRewrite::RewriteCond->new_from_string($line);
            };

            if ($cond) {
                next LINE if $skip_cur_rewrite;

                my $pattern = $cond->CondPattern();

                #If we are are redirecting the ENTIRE domain
                #(including www) then we remove any previous RewriteCond lines
                #that pertain to this domain.
                #
                #Note that it is still possible to have a particular
                #redirection that precedes a catch-all redirection by
                #submitting a string like '.?'.
                #
                if ($domain_to_remove) {

                    #See note above about “izzy”.
                    if ( $cond->TestString() eq '%{HTTP_HOST}' ) {
                        $skip_cur_rewrite = $pattern =~ /^\^(?:www\\?\.)?\Q${domain_to_remove}\E\$$/i;
                        $skip_cur_rewrite ||= $pattern =~ /^\^(?:www\\?\.)?\Q${quoted_domain_to_remove}\E\$$/i;
                    }

                    next LINE if $skip_cur_rewrite;
                }
            }
        }

        if ( $line =~ /^[\s\t]*RewriteRule/i ) {
            if ($skip_cur_rewrite) {
                $skip_cur_rewrite = 0;
                next;
            }
        }
        elsif ( $line =~ /^[\s\t]*RewriteEngine on/i ) {
            $hasrengine = 1;
        }

        push @HTACCESS, "$line\n";
    }

    if ( !$hasrengine ) {
        unshift @HTACCESS, "\nRewriteEngine on\n";
    }

    return ( $added, @HTACCESS );
}

#overridden in tests
*_get_docroot_for_domain = \&Cpanel::DomainLookup::getdocroot;

sub _open_htaccess {
    my ( $docroot, $module ) = @_;

    mkdir $docroot, 0755 if !-e $docroot;
    my $htaccess = "$docroot/.htaccess";
    my $trans;
    try {
        $trans = "$module"->new( 'path' => $htaccess, 'permissions' => $HTACCESS_PERMS, 'restore_original_permissions' => 1 );
    }
    catch {
        my $ex          = $_;
        my $msg         = "Failed to open “$htaccess”: " . Cpanel::Exception::get_string($_);
        my $log_message = "Failed to open “$htaccess”: $ex";
        Cpanel::Debug::log_info($log_message) if $Cpanel::Debug::level > 3;
        $Cpanel::CPERROR{$Cpanel::context} = $msg;
        die $msg;
    };

    return $trans;
}

sub _redirect_htaccess_cond {
    my ( $domain, $quoted_domain, $rdwww, $https_setting ) = @_;

    my @rules = ();
    if ( defined $https_setting ) {
        push @rules, "RewriteCond %{HTTPS} $https_setting\n";
        push @rules, "RewriteCond %{HTTP:X-Forwarded-SSL} !on\n";
    }

    #This one we shouldn’t even need since it will always match;
    #however, we look for it to identify wildcard redirections.
    if ( $domain eq '.*' ) {
        return ( @rules, "RewriteCond %{HTTP_HOST} ^.*\$\n" );
    }

    #TODO: This is inefficient; we should just match on “=$domain”.
    #But our parsing logic looks for this pattern to list the redirections,
    #so it’s not a small matter to change it.
    elsif ( $rdwww == 1 ) {
        return ( @rules, "RewriteCond %{HTTP_HOST} ^$quoted_domain\$\n" );
    }
    elsif ( $rdwww == 2 ) {
        return ( @rules, "RewriteCond %{HTTP_HOST} ^www\\.$quoted_domain\$\n" );
    }
    else {
        return (
            @rules,
            "RewriteCond %{HTTP_HOST} ^$quoted_domain\$ [OR]\n",
            "RewriteCond %{HTTP_HOST} ^www\\.$quoted_domain\$\n"
        );
    }
}

#NOTE: If given a nonexistent domain, this has the (useful) effect of ensuring
#that each redirection excludes AutoSSL and market SSL DCV check URLs.
sub setupredirection {
    my %OPTS                  = @_;
    my $docroot               = $OPTS{'docroot'};
    my $domain                = $OPTS{'domain'};
    my $redirecturl           = $OPTS{'redirecturl'};
    my $code                  = $OPTS{'code'};
    my $matchurl              = $OPTS{'matchurl'};
    my $exclude_dest_protocol = $OPTS{'exclude_dest_protocol'};

    my $https_setting;
    if ($exclude_dest_protocol) {
        $https_setting = 'on';
        if ( $redirecturl =~ m{^https}i ) {
            $https_setting = 'off';
        }
    }

    if ( !length $docroot ) {
        die 'Need “docroot”!';
    }

    if ( !length $domain ) {
        die 'Need “domain”!';
    }

    if ( !length $redirecturl ) {
        die 'Need “redirecturl”!';
    }

    Cpanel::LoadModule::load_perl_module('URI');
    my $uri_obj = URI->new($redirecturl);
    if ( !$uri_obj->scheme() || !$uri_obj->authority() ) {
        die "“$redirecturl” is not a valid redirect URL!";
    }

    $matchurl = q<> if !defined $matchurl;

    $matchurl =~ s{^\\?/+\??}{};    # not needed and problematic

    # TODO: caller does not add $ but user entered a $ at the end to match a  literal dollar sign, will this circumstance happen ?
    my $trailing_anchor = $matchurl =~ s{\$$}{} ? '$' : '';    # caller adds the $, this function adds the ^ below... so we take it off here and add it back when we add the ^

    my $usewildcard_capture = 0;
    my $trailing_wildcard   = $matchurl =~ s{\(\.\*\)$}{} ? '(.*)' : '';
    if ($trailing_wildcard) {
        $usewildcard_capture = 1;
    }
    else {
        $trailing_wildcard = $matchurl =~ s{\.\*$}{} ? '.*' : '';
    }

    my $trailing_optional_slash = $matchurl =~ s{/+\?$}{} ? '\/?' : '';    # the optional trailing slash (i.e. \/?) isn't really needed butfor backwardness sake...

    my $rewriteopts = $OPTS{'rewriteopts'};
    my $rdwww       = $OPTS{'rdwww'};

    $rdwww ||= 0;                                                          #default to redirecting both www and non-www

    if ( !$code || ( $code != 301 && $code != 302 ) ) { $code = 301; }
    $rewriteopts = ( defined $rewriteopts ? $rewriteopts : "R=$code,L" );

    my $quoted_domain = $domain && Cpanel::UTF8::Utils::quotemeta($domain);

    my ( $htaccess_trans, $exception );
    try {
        $htaccess_trans = open_htaccess_rw($docroot);
    }
    catch {
        $exception = $_;
    };

    if ($exception) {
        return ( 0, Cpanel::Exception::get_string_no_id($exception) );
    }

    my ( undef, @HTACCESS ) = _normalize_htaccess_lines(
        $htaccess_trans,
        $matchurl ? undef : $domain,
    );

    my $userequri = 0;

    if ( !$usewildcard_capture && $rewriteopts =~ tr/P// ) {
        $userequri = 1;
    }

    push @HTACCESS, _redirect_htaccess_cond( $domain, $quoted_domain, $rdwww, $https_setting );

    $redirecturl =~ s{"}{'}g;                                       # rewrite rules do not tolerate double quotes (RewriteRule: bad flag delimiters) regardless of escaping
    $redirecturl = Cpanel::UTF8::Utils::quotemeta($redirecturl);    # since it will now be in double quotes

    #WTF .. ?!?!?
    $matchurl = Cpanel::StringFunc::UnquoteMeta::unquotemeta($matchurl);    # in case they do partial escaping
    $matchurl = Cpanel::Encoder::URI::uri_decode_str_noform($matchurl);     # mod_rewrite unescapes characters before matching
    $matchurl = Cpanel::UTF8::Utils::quotemeta($matchurl);

    my $default_reg    = $trailing_wildcard ? "^$trailing_wildcard\$"                                                : '^/?$';
    my $matchthis_str  = $matchurl          ? "^$matchurl$trailing_optional_slash$trailing_wildcard$trailing_anchor" : $default_reg;
    my $redirectto_str = qq{"$redirecturl} . ( $usewildcard_capture ? '$1' : ( $userequri ? '%{REQUEST_URI}' : '' ) ) . '"';
    push @HTACCESS, "RewriteRule $matchthis_str $redirectto_str [$rewriteopts]\n\n";

    $htaccess_trans->set_data( \join( '', @HTACCESS ) );

    my ( $status, $msg ) = test_and_install_htaccess(
        'installdir'     => $docroot,
        'htaccess_trans' => $htaccess_trans,
    );

    return ( $status, $msg );
}

sub disableredirection {
    my $docroot     = shift;
    my $domain      = shift;
    my $matchurl    = shift;
    my $redirecturl = Cpanel::UTF8::Utils::quotemeta( shift || '' );

    my ( $htaccess_trans, $exception );
    try {
        $htaccess_trans = open_htaccess_rw($docroot);
    }
    catch {
        $exception = $_;
    };

    if ($exception) {
        return ( 0, Cpanel::Exception::get_string_no_id($exception) );
    }

    my @HTACCESS;

    my $currentrule = q<>;
    my $currentrule_matches_domain;

    my $regexmatchurl = $matchurl || '';
    $regexmatchurl =~ s/\(?\.\*\)?$//;
    $regexmatchurl =~ s/^\///g;
    my $quoted_regexmatchurl = Cpanel::UTF8::Utils::quotemeta($regexmatchurl);

    #This is the one that *should* match, but users may forget
    my $quoted_domain = Cpanel::UTF8::Utils::quotemeta($domain);

    Cpanel::LoadModule::load_perl_module('Cpanel::ApacheConf::ModRewrite::RewriteCond');
    Cpanel::LoadModule::load_perl_module('Cpanel::ApacheConf::ModRewrite::RewriteRule');
  LINE:
    foreach my $line ( split( m{\n}, ${ $htaccess_trans->get_data() } ) ) {
        if ( $line =~ m/^\s*RewriteCond/i ) {
            $currentrule .= "$line\n";

            if ( !$currentrule_matches_domain ) {

                my $cond;

                #Don’t bother warn()ing on an unparsable value because it could
                #be one of the variants of RewriteCond that we don’t parse.
                try {
                    $cond = Cpanel::ApacheConf::ModRewrite::RewriteCond->new_from_string($line);
                };

                if ( $cond && $cond->TestString() eq '%{HTTP_HOST}' ) {

                    #These should handle the majority of cases.
                    $currentrule_matches_domain = $cond->pattern_matches($domain);
                    $currentrule_matches_domain ||= $cond->pattern_matches("www.$domain");

                    #legacy
                    $currentrule_matches_domain ||= do {

                        #Should match all of the following, case-insensitively:
                        #   ^izzy\.org$         <== correct
                        #   ^izzy.org$
                        #   ^www\.izzy\.org$    <== correct
                        #   ^www.izzy\.org$
                        #   ^www\.izzy.org$
                        #   ^www.izzy.org$
                        my $domain_regexp = qr<
                            \^
                            (?:www\\?\.)?
                            (?:
                                \Q$domain\E
                                |
                                \Q$quoted_domain\E
                            )
                            \$
                        >xi;

                        $cond->CondPattern() =~ m<$domain_regexp>;
                    };
                }
            }

            next LINE;
        }
        elsif ( $line =~ m/^[\s\t]*RewriteRule/i ) {

            #Keep the rule if it doesn’t match the given domain.
            my $keep_rule = !$currentrule_matches_domain;

            my $rule;

            #The rule matches the domain, hm? Well, but we still should
            #keep it if there is no match URL given and the rule has these flags.
            #(This is legacy logic whose rationale seems obscure.)
            if ( !$keep_rule ) {

                try {
                    $rule = Cpanel::ApacheConf::ModRewrite::RewriteRule->new_from_string($line);
                }
                catch {
                    warn "Failed to parse RewriteRule: “$line”!";
                };

                #If we failed to parse, then assume we need to keep the rule.
                $keep_rule = !$rule || !$matchurl && !grep { !$rule->has_flag($_) } qw(
                  proxy
                  qsappend
                  last
                );
            }

            #Finally, if the rule matches the domain and the above (weird)
            #check didn’t “redeem” this rule from being deleted, check that
            #the given match URL corresponds to this rule.
            if ( !$keep_rule ) {

                my $post_url_fuzz_qr = qr<(?: \\? / )? (?: \\? \?)?>x;

                my $pattern_start_qr = qr<
                    \^

                    #leading junk … ?
                    (?: \\? /+ \?? )?

                    (?: \Q$regexmatchurl\E | \Q$quoted_regexmatchurl\E )

                    #allow “fuzz” after the URL
                    $post_url_fuzz_qr
                >x;

                #We always match against the source URL; additionally,
                #if a target URL was given, match against that, too.
                if ($redirecturl) {

                    #The original regexp that got unrolled into this logic
                    #in v60 is as follows. There were actually two regexps, but
                    #they differed only in the presence of $regexmatchurl
                    #vs. $quoted_regexmatchurl. The code below checks for both.
                    #/
                    #   ^[\s\t]* RewriteRule \s*
                    #   \^ (?:\\?\/+\??)?
                    #   \Q$regexmatchurl\E
                    #   \\? \/? \??
                    #   (
                    #       \(? \. \* \)? \$?
                    #       |
                    #       \$
                    #       |
                    #       \%\{REQUEST_URI\}
                    #   )?
                    #   \s+
                    #   \"?
                    #       \Q$redirecturl\E
                    #       \\? \/? \??
                    #       (
                    #           \(? \. \* \)? \$
                    #           |
                    #           \\ \( \\ \. \\ \* \\ \) \$
                    #           |
                    #           \$1
                    #           |
                    #           \%\{REQUEST_URI\}
                    #       )
                    #   \"?
                    #/x

                    #It would be nice to use pattern_matches() instead
                    #of examining the pattern itself, but there are too many
                    #historical possibilities for that to be feasible.
                    $keep_rule = $rule->Pattern() !~ m<
                        \A
                        $pattern_start_qr

                        (?:
                            \Q.*\E \$?
                            |
                            \Q(.*)\E \$?
                            |
                            \$
                            |

                            #In the absence of documentation, it seems
                            #unclear what exactly this is doing here.
                            #Apache 2.2’s docs don’t describe variable
                            #interpolation in RewriteRule “Pattern”s.
                            #If this does match anything, it’s probably
                            #faulty logic that put it there.
                            #As such, we don’t test for it.
                            \Q%{REQUEST_URI}\E
                        )?
                        \z
                    >x;

                    $keep_rule ||= $rule->Substitution() !~ m<
                        \A
                        $redirecturl    #already got escaped above

                        #allow “fuzz” after the URL
                        $post_url_fuzz_qr

                        #The wildcard stuff doesn’t seem sensible here
                        #since the Substitution string isn’t a regexp anyway.
                        #Leave it in, but we don’t test for it.
                        (?:
                            \Q.*\E \$
                            |
                            \Q(.*)\E \$
                            |
                            \Q\(\.\*\)\E \$
                            |

                            #These two seem to make sense.
                            \$1
                            |
                            \Q%{REQUEST_URI}\E
                        )
                        \z
                    >x;

                }
                else {
                    #/^ [\s\t]* RewriteRule \s*
                    #   \^
                    #   (?: \\? \/+ \?? )?
                    #   \Q$regexmatchurl\E
                    #   \\? \/? \??
                    #   (
                    #       \(? \. \* \)? \$?
                    #       |
                    #       \\ \( \\ \. \\ \* \\ \) \$
                    #       |
                    #       \$
                    #       |
                    #       \%\{REQUEST_URI\}
                    #       |
                    #       $
                    #   )
                    #   \s+
                    #/

                    $keep_rule = $rule->Pattern() !~ m<
                        \A
                        $pattern_start_qr

                        (?:
                            \Q.*\E \$?
                            |
                            \Q(.*)\E \$?
                            |
                            \Q\(\.\*\)\E \$
                            |
                            \$
                            |

                            #As above, the purpose of this seems unclear.
                            #As such, we don’t test for it.
                            \Q%{REQUEST_URI}\E
                        )
                        \z
                    >x;
                }
            }

            if ($keep_rule) {

                #read it as its not what we want
                push @HTACCESS, map { $_ . "\n" } split( /\n/, $currentrule );
                push @HTACCESS, "$line\n";
            }

            $currentrule                = '';
            $currentrule_matches_domain = 0;

            next LINE;
        }

        push @HTACCESS, "$line\n";
    }

    if ( !grep( /^\s*Rewrite(Cond|Rule)/i, @HTACCESS ) ) {
        @HTACCESS = grep ( !/^\s*RewriteEngine\s*\"?on/i, @HTACCESS );
    }

    $htaccess_trans->set_data( \join( '', @HTACCESS ) );

    my ( $status, $msg ) = test_and_install_htaccess(
        'installdir'     => $docroot,
        'htaccess_trans' => $htaccess_trans,
    );

    return ( $status, $msg );
}

sub redirect_type {
    my $rtype = shift;
    if   ( $rtype && $rtype =~ m/(?:301|perm)/i ) { return 'permanent'; }
    else                                          { return 'temporary'; }
}

sub test_and_install_htaccess {
    my %OPTS           = @_;
    my $installdir     = $OPTS{'installdir'};
    my $htaccess_trans = $OPTS{'htaccess_trans'};

    if ( !try { $htaccess_trans->isa('Cpanel::Transaction::File::Raw') } ) {
        Cpanel::Debug::log_die("test_and_install_htaccess requires htaccess_trans => isa(Cpanel::Transaction::File::Raw), not “$OPTS{'htaccess_trans'}”");
    }

    my $htaccess_ref = $htaccess_trans->get_data();
    $$htaccess_ref =~ s/\n\n+/\n\n/g;

    my $rand = Cpanel::Rand::Get::getranddata(32);

    my $testfile = $installdir . '/.htaccess.' . $rand;

    if ( -e $testfile ) {
        Cpanel::Debug::log_die("test_and_install_htaccess could not generate random data");
    }

    my $test_fh;
    if ( !open( $test_fh, '>', $testfile ) ) {
        Cpanel::Debug::log_die("test_and_install_htaccess could not create test htaccess file “$testfile”: $!");
    }

    print {$test_fh} <<EOM;

<Directory "/">
    AllowOverride All
    Options All
</Directory>

EOM

    my $to_delete = Cpanel::Finally->new( sub { unlink $testfile } );

    my $apache_version_key = Cpanel::HttpUtils::Version::get_current_apache_version_key();

    #do not check allow and deny because they won't be allowed here
    my $httest = join( "\n", grep( !/^\s*(?:php|suPHP_ConfigPath|authname|authtype|authuserfile|authgroupfile|require|deny|order|allow)\s*/i, split( /\n/, $$htaccess_ref ) ) );

    if ( $apache_version_key eq '2_4' ) {
        $httest =~ s/<Limit.+?<\/Limit>//xmigs;
        $httest =~ s/<RequireAll.+?<\/RequireAll>//xmigs;
    }

    print {$test_fh} _wrap_lines_not_already_inside_directory_block_with_directory_block( $httest, $installdir );
    close $test_fh;

    if ( my $error = _get_error_in_htaccess($testfile) ) {
        $htaccess_trans->close_or_die();

        #XXX: This should return plain text, not HTML.
        #But at least one public API expects HTML here. :(
        my $html_testconf = Cpanel::Encoder::Tiny::safe_html_encode_str($error);

        return ( 0, "Apache detected an error in the Rewrite config. <pre>$html_testconf</pre> Please try again." );
    }

    my ( $status, $message ) = Cpanel::OrDie::convert_die_to_multi_return( sub { return $htaccess_trans->save_and_close_or_die() } );
    return ( $status, $message ) if !$status;
    return ( 1,       "Htaccess Installed" );
}

# case CPANEL-11033: Enclose the .htaccess test file in <Directory...>
# so its tested in the right context when we do the httpd conf test.
sub _wrap_lines_not_already_inside_directory_block_with_directory_block {
    my ( $httest, $installdir ) = @_;

    my $quoted_installdir = Cpanel::UTF8::Utils::quotemeta($installdir);
    my $unclosed_ifmodule = 0;

    my $START_ENCLOSE = qq{\n<Directory "$quoted_installdir">\n};
    my $END_ENCLOSE   = qq{\n</Directory>\n};

    my $htresult = $START_ENCLOSE;
    foreach my $line ( split( m{^}, $httest ) ) {
        if ( $line =~ m{^\s*<\s*IfModule}i ) {
            $unclosed_ifmodule++;
            $htresult .= $line;
        }
        elsif ( $line =~ m{^\s*<\s*\/\s*IfModule}i ) {
            $unclosed_ifmodule--;
            $htresult .= $line;
        }
        elsif ( $line =~ m{^\s*<\s*(?:Location|Directory)}i ) {
            $htresult .= $END_ENCLOSE;
            $htresult .= $line;
        }
        elsif ( $line =~ m{^\s*<\s*\/\s*(?:Location|Directory)}i ) {
            $htresult .= $line;
            $htresult .= $START_ENCLOSE;
        }
        else {
            $htresult .= $line;
        }
    }

    if ($unclosed_ifmodule) {
        for ( 1 .. $unclosed_ifmodule ) {

            # Apache does not care about unclosed
            # IfModule unless they are in a <Directory> block
            # so we must close them all before the final </Directory>
            $htresult .= "\n</IfModule>\n";
        }
    }

    $htresult .= $END_ENCLOSE;
    return $htresult;
}

sub get_error_in_current_htaccess {
    my ($docroot) = @_;

    return _get_error_in_htaccess("$docroot/.htaccess");
}

sub _get_error_in_htaccess {
    my ($testfile) = @_;

    my $testconf = _check_path($testfile);

    #ap_mm_create and RewriteBase .. just pass it though :(
    if ( $testconf !~ m/Syntax OK/mi && $testconf !~ m/ap_mm_create/mi && $testconf !~ m/RewriteBase/mi ) {
        return $testconf;
    }

    return undef;
}

#overridden in tests for speed
sub _check_path {
    return Cpanel::ApacheConf::Check::check_path(shift)->stderr();
}

sub _add_missing_dcv_exclusions {
    my ( $exclusions_ar, $target_ar ) = @_;

    my @exclusions = @$exclusions_ar;    # Make a copy since we modify

    Cpanel::LoadModule::load_perl_module('Cpanel::ApacheConf::ModRewrite::Utils');
    $_ = Cpanel::ApacheConf::ModRewrite::Utils::escape_for_stringify($_) for @exclusions;

    #Sort them for testability
    push @${target_ar}, map { "RewriteCond %{REQUEST_URI} !$_\n" } sort grep { length } @exclusions;

    return 1;
}

=head2 open_htaccess_ro(DOCROOT, MODE)

Safely open the htaccess file read-only.

NOTE: Preserved for backward compatibility.

=head3 ARGUMENTS

=over

=item DOCROOT - string

User owned path to the directory being secured.

=back

=head3 RETURNS

Cpanel::Transaction::File::RawReader

=cut

sub open_htaccess_ro {
    my ($docroot) = @_;
    return Cpanel::HttpUtils::Htaccess::open( $docroot, $MODES{READONLY} );
}

=head2 open_htaccess_rw(DOCROOT)

Safely open the htaccess file read-write.

NOTE: Preserved for backward compatibility.

=head3 ARGUMENTS

=over

=item DOCROOT - string

User owned path to the directory being secured.

=back

=head3 RETURNS

Cpanel::Transaction::File::Raw

=cut

sub open_htaccess_rw {
    my ($docroot) = @_;
    return Cpanel::HttpUtils::Htaccess::open( $docroot, $MODES{READWRITE} );
}

=head2 open(DOCROOT, MODE)

Safely open the file for the given mode.

=head3 ARGUMENTS

=over

=item DOCROOT - string

User owned path to the directory being secured.

=item MODE - one of the values in the MODES hash above.

For readonly file access:

  my $transaction = Cpanel::HttpUtils::Htaccess::open(
    '/home/tommy/public_html',
    $Cpanel::HttpUtils::Htaccess::MODES{READONLY}
  );

  ...

For read/write file access:

  my $transaction = Cpanel::HttpUtils::Htaccess::open(
    '/home/tommy/public_html',
    $Cpanel::HttpUtils::Htaccess::MODES{READWRITE}
  );

...

=back

=head3 RETURNS

One of the following types depending on the mode requested:

=over

=item Cpanel::Transaction::File::RawReader

When requesting readonly file access

=item Cpanel::Transaction::File::Raw

When requesting readwrite file access.

=back

=head3 THROWS

=over

=item When the file cannot be opened in the mode.

=item When the file does not have the correct permissions for the mode.

=back

=cut

sub open {
    my ( $docroot, $mode ) = @_;
    _validate_ownership($docroot) if $mode eq $MODES{READWRITE};

    my $module   = $mode;
    my $htaccess = "$docroot/.htaccess";

    my $transaction;
    eval { $transaction = "$module"->new( path => $htaccess, permissions => $HTACCESS_PERMS, 'restore_original_permissions' => 1 ); };
    if ( my $exception = $@ ) {
        my $log_message = "Failed to open “$htaccess”: $exception";
        Cpanel::Debug::log_info($log_message) if $Cpanel::Debug::level > 3;
        die $exception;
    }

    return $transaction;
}

=head2 _validate_ownership(PATH) [PRIVATE]

Validate the path is controlled by the current user.

=head3 ARGUMENTS

=over

=item PATH - string

Path to the directory we are checking ownership for.

=back

=head3 RETURNS

1 if ownership is valid.

=head3 THROWS

=over

=item CannotReplaceFile exception if the current user does not own the path

=back

=cut

sub _validate_ownership {
    my ($path) = @_;

    my $hta_uid = ( stat $path )[4];

    if ( defined($hta_uid) && $hta_uid != $> ) {
        die Cpanel::Exception::create(
            'CannotReplaceFile',
            [
                pid    => $$,
                euid   => $>,
                egid   => $),
                path   => $path,
                fs_uid => $hta_uid
            ]
        );
    }
    return 1;
}

=head2 _quoted(TEXT) [PRIVATE]

Quote the input string with double quotes. Correctly escapes any double quotes already in the string.

=cut

sub _quoted {
    return '"' . _escape( $_[0] ) . '"';
}

=head2 _escape(TEXT) [PRIVATE]

Escapes any double quotes and \ in the passed in string.

=cut

sub _escape {
    my ($text) = @_;
    $text =~ s{\\}{\\\\}g;
    $text =~ s/"/\\"/g;
    return $text;
}

=head2 _unescape(TEXT) [PRIVATE]

unescapes any double quotes or \ in the passed in string.

=cut

sub _unescape {
    my ($text) = @_;
    $text =~ s/\\"/"/g;
    $text =~ s{\\\\}{\\}g;
    return $text;
}

1;
