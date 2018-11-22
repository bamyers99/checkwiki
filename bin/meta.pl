#! /usr/bin/env perl

###########################################################################
##
##         FILE: meta.pl
##
##        USAGE: ./meta.pl -c checkwiki.cfg
##
##  DESCRIPTION: Updates the meta database
##
##       AUTHOR: Bryan White
##      LICENCE: GPLv3
##      VERSION: 12/05/2016
##
###########################################################################

use strict;
use warnings;

use DBI;
use Encode;
use Getopt::Long
  qw(GetOptionsFromString :config bundling no_auto_abbrev no_ignore_case);

use LWP::UserAgent;
use URI::Escape;
use MediaWiki::API;

binmode( STDOUT, ":encoding(UTF-8)" );

our @Projects;

#Database configuration
our $DbName;
our $DbServer;
our $DbUsername;
our $DbPassword;
our $dbh;

our $project;

#Meta variables
our @Namespace_cat;          # All namespaces for categorys
our @Namespace_image;        # All namespaces for images
our @Namespace_templates;    # All namespaces for templates
our $Image_regex = q{};      # Regex used in get_images()
our $Cat_regex   = q{};      # Regex used in get_categories()
our $User_regex  = q{};      # Regex used in error_095_user_signature();
our $Draft_regex = q{};      # Regex used in error_095_user_signature();
our $Defaultsort = q{};

##########################################################################
## MAIN PROGRAM
##########################################################################

my @Options = (
    'database|d=s' => \$DbName,
    'host|h=s'     => \$DbServer,
    'password=s'   => \$DbPassword,
    'user|u=s'     => \$DbUsername,
);

GetOptions(
    'c=s' => sub {
        my $f = IO::File->new( $_[1], '<' )
          or die( "Can't open " . $_[1] . "\n" );
        local ($/);
        my $s = <$f>;
        $f->close();
        my ( $Success, $RemainingArgs ) = GetOptionsFromString( $s, @Options );
        die unless ( $Success && !@$RemainingArgs );
    }
);

#--------------------

open_db();
get_projects();

foreach (@Projects) {
    $project = $_;
    my $Language;

    $User_regex  = q{};
    $Draft_regex = q{};
    $Cat_regex   = q{};

    clearTable();
    print 'Working on:' . $project . "\n";

    my $ServerName = $project;
    if (
        !(
               $ServerName =~ s/^nds_nlwiki$/nds-nl.wikipedia.org/
            || $ServerName =~ s/^([a-z]+)wiki$/$1.wikipedia.org/
            || $ServerName =~ s/^([a-z]+)wikisource$/$1.wikisource.org/
            || $ServerName =~ s/^([a-z]+)wikiversity$/$1.wikiversity.org/
            || $ServerName =~ s/^([a-z]+)wiktionary$/$1.wiktionary.org/
            || $ServerName =~ s/^([a-z]+)wikivoyage$/$1.wikivoyage.org/
        )
      )
    {
        die( "Couldn't calculate server name for project" . $project . "\n" );
    }

    ($Language) = $ServerName =~ /^([a-z]*)/;

    my $url = 'https://' . $ServerName . '/w/api.php';

    # Setup MediaWiki::API
    my $mw = MediaWiki::API->new();
    $mw->{config}->{api_url} = $url;

    # See https://www.mediawiki.org/wiki/API:Siteinfo
    my $res = $mw->api(
        {
            action => 'query',
            meta   => 'siteinfo',
            siprop =>
              'general|namespaces|namespacealiases|statistics|magicwords',
        }
    ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details} . "\n";

    foreach my $id ( keys %{ $res->{query}->{namespaces} } ) {
        my $name      = $res->{query}->{namespaces}->{$id}->{q{*}};
        my $canonical = $res->{query}->{namespaces}->{$id}->{'canonical'};

        # Store special namespaces in convenient variables.
        if ( $id == 2 or $id == 3 ) {
            $name       = lc($name);
            $User_regex = $User_regex . '\[\[' . $name . q{:|};
        }
        if ( $id == 118 or $id == 119 ) {
            $name        = lc($name);
            $Draft_regex = $Draft_regex . '\[\[' . $name . q{:|};
        }
        if ( $id == 6 ) {
            @Namespace_image = ( $name, $canonical );
            $Image_regex = $name;
        }
        if ( $id == 10 ) {
            @Namespace_templates = ($name);
            push( @Namespace_templates, $canonical ) if ( $name ne $canonical );
        }
        if ( $id == 14 ) {
            @Namespace_cat = ($name);
            $Cat_regex     = $name;
            if ( $name ne $canonical ) {
                push( @Namespace_cat, $canonical );
                $Cat_regex = $name . q{|} . $canonical;
            }
        }
    }
    foreach my $entry ( @{ $res->{query}->{namespacealiases} } ) {
        my $name = $entry->{q{*}};
        if ( $entry->{id} == 2 or $entry->{id} == 3 ) {
            $name       = lc($name);
            $User_regex = $User_regex . '\[\[' . $name . q{:|};
        }
        if ( $entry->{id} == 6 ) {
            push( @Namespace_image, $name );
            $Image_regex = $Image_regex . q{|} . $name;
        }
        if ( $entry->{id} == 10 ) {
            push( @Namespace_templates, $name );
        }
        if ( $entry->{id} == 14 ) {
            push( @Namespace_cat, $name );
            $Cat_regex = $Cat_regex . q{|} . $name;
        }

    }

    foreach my $id ( @{ $res->{query}->{magicwords} } ) {
        my $aliases = $id->{aliases};
        my $name    = $id->{name};
        $Defaultsort = $aliases if ( $name eq 'defaultsort' );
    }

    foreach my $value ( @{$Defaultsort} ) {
        my $sth = $dbh->prepare(
			'INSERT IGNORE INTO cw_meta (project, templates, metaparam ) VALUES (?, ?, ?)'
        );
        $sth->execute( $project, $value, 'magicword_defaultsort' )
          or die "Cannot execute: " . $sth->errstr . "\n";
    }
    
    if ( exists $res->{query}->{general}->{rtl} ) {
        my $sth = $dbh->prepare(
			'INSERT IGNORE INTO cw_meta (project, templates, metaparam ) VALUES (?, ?, ?)'
        );
        $sth->execute( $project, '1', 'rtl_text_dir' )
          or die "Cannot execute: " . $sth->errstr . "\n";
    }

    chop($Draft_regex);    # Drop off final '|'
    chop($User_regex);

    add_array_to_db( 'namespace_cat',       \@Namespace_cat );
    add_array_to_db( 'namespace_templates', \@Namespace_templates );
    add_scalar_to_db( 'image_regex', $Image_regex );
    add_scalar_to_db( 'cat_regex',   $Cat_regex );
    add_scalar_to_db( 'user_regex',  $User_regex );
    add_scalar_to_db( 'draft_regex', $Draft_regex );
    print "\n";

}

##########################################################################
## OPEN DATABASE
##########################################################################

sub open_db {

    $dbh = DBI->connect(
        'DBI:mysql:'
          . $DbName
          . ( defined($DbServer) ? ':host=' . $DbServer : q{} ),
        $DbUsername,
        $DbPassword,
        {
            RaiseError        => 1,
            AutoCommit        => 1,
            mysql_enable_utf8mb4 => 1
        }
    ) or die( "Could not connect to database: " . DBI::errstr() . "\n" );

	$dbh->do('SET NAMES utf8mb4')
	   or die($dbh->errstr);

    return ();
}

###########################################################################
## CLOSE DATABASE
###########################################################################

sub close_db {
    $dbh->disconnect();

    return ();
}

###########################################################################
### GET PROJECT NAMES FROM DATABASE (ie enwiki, dewiki)
############################################################################

sub get_projects {

    print "Load projects from db\n";
    my $result = q();
    my $sth = $dbh->prepare('SELECT project FROM cw_overview ORDER BY project;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute or die "Cannot execute: " . $sth->errstr . "\n";

    my $project_counter = 0;
    while ( my $arrayref = $sth->fetchrow_arrayref() ) {

        foreach (@$arrayref) {
            $result = $_;
        }

        push( @Projects, $result );
        $project_counter++;
    }

    return ();
}

###########################################################################
## DELETE INFO FROM DATABASE
###########################################################################

sub clearTable {

    my $sth = $dbh->prepare('DELETE FROM cw_meta WHERE Project = ?;')
      || die "Can not prepare statement: $DBI::errstr\n";
    $sth->execute($project) or die "Cannot execute: " . $sth->errstr . "\n";

    return ();

}

###########################################################################
## ADD  ARRAY TO DATABASE
###########################################################################

sub add_array_to_db {
    my ( $meta_param, $array_ref ) = @_;
    my @array = @{$array_ref};

    foreach my $value (@array) {

        if ( $value ne q{} ) {

            $value =~ s/^\s+|\s+$//;

            print $project . q{  } . $meta_param . q{  } . $value . "\n";
            my $sth = $dbh->prepare(
'INSERT IGNORE INTO cw_meta (project, templates, metaparam ) VALUES (?, ?, ?)'
            );
            $sth->execute( $project, $value, $meta_param )
              or die "Cannot execute: " . $sth->errstr . "\n";
        }
    }

    return ();
}

###########################################################################
## ADD SCALAR TO DATABASE
###########################################################################

sub add_scalar_to_db {
    my ( $meta_param, $value ) = @_;

    if ( $value ne q{} ) {

        $value =~ s/^\s+|\s+$//;

        print $project . q{  } . $meta_param . q{  } . $value . "\n";
        my $sth = $dbh->prepare(
'INSERT IGNORE INTO cw_meta (project, templates, metaparam ) VALUES (?, ?, ?)'
        );
        $sth->execute( $project, $value, $meta_param )
          or die "Cannot execute: " . $sth->errstr . "\n";
    }

    return ();
}
