$.support.history = !! ( window.history && history.pushState )

Number.prototype.approximate = ->
	return @ if @ < 1000

	thousands = Math.round( @ / 100 ) / 10
	return thousands.toString() + 'K' if thousands < 1000

	millions = Math.round( thousands / 100 ) / 10
	millions.toString() + 'M'

roundNumber = ( number, decimals = 0 ) ->
	Math.round( number * Math.pow( 10, decimals ) ) / Math.pow( 10, decimals )

getPermalinkQuery = ( query ) ->
	results = {}
	conConMap =
		conversions_control:    'cc', # con con
		samples_control:        'sc', # con sam
		conversions_experiment: 'ce', # test con
		samples_experiment:     'se'  # test sam
		significance:           'significance'
		name:           'name'

	$.map query, ( value, key ) ->
		results[ conConMap[ key ] ] = value

	results

isPermalinkPage = ->
	return false unless getParameter 'cc'
	return false unless getParameter 'sc'
	return false unless getParameter 'ce'
	return false unless getParameter 'se'

	true

getTemplateOutput = ( templateName, input ) ->
	template = Handlebars.templates[templateName]
	template input

renderError = ( error ) ->
	html = getTemplateOutput 'error', { error }
	printResult html

renderResults = ( stat_results, query ) ->
	results = []

	percentagize = ( numbers ) ->
		percents = {}

		$.each numbers, ( key, value ) ->
			value = 100 * value

			# Percents over 1000 don't need decimals
			decimals = if ( value >= 1000 ) then 0 else 1
			percents[ key ] = roundNumber value, decimals

		percents

	permalink = "http://#{window.location.host}?" + getQueryString query

	# Figure out the winner
	winner_significance = Math.max stat_results.significance.results.experiment, stat_results.significance.results.control
	is_significant = winner_significance > getParameter 'significance'

	conf_results = stat_results.confidence.results
	winner = if conf_results.experiment.average > conf_results.control.average
		'Variant A'
	else
		'Variant B'

	# Control
	results.push $.extend
		title: 'Variant A'
		chart: stat_results.confidence.chart.control
		is_winner: winner is 'original' and is_significant
		inputs:
			conversions: parseInt( query.conversions_control, 10 ).approximate()
			samples: parseInt( query.samples_control, 10 ).approximate()
	, percentagize stat_results.confidence.results.control

	 # Experiment
	results.push $.extend
		title: 'Variant B'
		chart: stat_results.confidence.chart.experiment
		is_winner: winner is 'experiment' and is_significant
		inputs:
			conversions: parseInt( query.conversions_experiment, 10 ).approximate()
			samples: parseInt( query.samples_experiment, 10 ).approximate()
	, percentagize stat_results.confidence.results.experiment

	# Significance
	results.push $.extend
		title: 'Significance'
		chart: stat_results.significance.chart
		winner: "#{winner.charAt(0).toUpperCase()}#{winner.slice(1)}"
	, percentagize { average: winner_significance }

	# Improvement
	results.push $.extend
		title: 'Improvement'
		chart: stat_results.improvement.chart
	, percentagize stat_results.improvement.results

	html = getTemplateOutput 'results', { results, permalink }
	printResult html

printResult = ( html, options = {} ) ->
	$('.results').fadeOut 200, ->
		$(this).hide().delay( 300 ).html( html ).fadeIn options.speed

pushState = ( query ) ->
	url = '?' + getQueryString query
	history.pushState query, '', url if $.support.history

isEmbed = ->
	! $('.header').is( ':visible' )

isNewQuery = ( queryString ) ->
	return queryString != window.location.search

getQueryString = ( query ) ->
	$.param( getPermalinkQuery query )

getResults = ( query, options = {} ) ->
	# Optional param
	query.significance = if !query.significance or _.isNaN query.significance
		.90
	else if _.isString query.significance
		query.significance.replace /\D+$/, ''
	else
		query.significance

	query.significance = parseFloat query.significance, 10
	query.significance /= 100 if 1 < query.significance < 100

	lastQuery = window.location.search
	newQuery  = '?' + getQueryString query

	# Maintain state
	pushState query if ! isEmbed() && ( isNewQuery( newQuery ) || ! history.state )

	# Don't run the same query twice in a row
	return false if not options.force && lastQuery is newQuery

	queryAPI( query ).done ( stat_results ) ->
		$('.alert').fadeOut()

		# Check for errors
		return renderError stat_results.error if stat_results.error

		$('body').removeClass( 'home' ).addClass 'permalink'
		renderResults stat_results, query

syncFormWithPermalink = ->
	$("input#control-conversions").val getParameter( 'cc' )
	$("input#control-samples").val getParameter( 'sc' )
	$("input#experiment-conversions").val getParameter( 'ce' )
	$("input#experiment-samples").val getParameter( 'se' )
	$("input#significance").val getParameter( 'significance' ) || .90

queryAPI = ( query ) ->
	# So that we get a significance chart for whichever version wins
	query.winners_perspective = true
	$.getJSON 'api?' + $.param query

getParameter = ( paramName ) ->
	searchString = window.location.search.substring 1
	params = searchString.split '&'

	for param in params
		val = param.split( '=' )
		return unescape val[ 1 ] if val[ 0 ] is paramName

	null

isFormComplete = ->
	return false unless $('input#control-conversions').val()
	return false unless $('input#control-samples').val()
	return false unless $('input#experiment-conversions').val()
	return false unless $('input#experiment-samples').val()
	return false unless $('input#significance').val()

	true

$ ->
	# Bind popstate listener
	if $.support.history
		$(window).on 'popstate', ( event ) ->
			state = event.originalEvent.state
			if state
				getResults state, { force: true }
				syncFormWithPermalink()

	# Focus on the first input
	$("form :input:visible:first").focus()

	# Listen for form submit
	$("form").on 'submit', ( event ) ->
		event.preventDefault()

		# Don't submit incomplete forms
		return false unless isFormComplete()

		getResults
			conversions_control:    $('input#control-conversions').val()    # con con
			samples_control:        $('input#control-samples').val()        # con sam
			conversions_experiment: $('input#experiment-conversions').val() # test con
			samples_experiment:     $('input#experiment-samples').val()     # test sam
			significance:           $('input#significance').val()

	# Auto-load results on permalink pages
	if isPermalinkPage()
		syncFormWithPermalink()

		getResults
			conversions_control:    getParameter( 'cc' ) # con con
			samples_control:        getParameter( 'sc' ) # con sam
			conversions_experiment: getParameter( 'ce' ) # test con
			samples_experiment:     getParameter( 'se' ) # test sam
			significance:           getParameter( 'significance' )
		, { force: true }

	else
		$('input#significance').val .90
		$('body').removeClass( 'permalink' ).addClass 'home'
		$('.alert-info').delay( 1400 ).fadeIn 'slow'

	# Auto-submit the form
	$( 'form input[type=text]' ).keyup ->
		clearTimeout @keyup_timer
		@keyup_timer = setTimeout ->
			$('form').submit()
		, 800

	# Extra options
	$( '#conconjr' ).on 'click', ->
		$( '.form-extra' ).slideToggle().find( 'input' ).focus()
