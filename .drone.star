config = {
	'app': 'data_exporter',
	'rocketchat': {
		'channel': 'builds',
		'from_secret': 'private_rocketchat'
	},

	'branches': [
		'master'
	],

	'appInstallCommand': 'make',

	'codestyle': True,

	'phpstan': True,

	'phan': True,

	'phpunit': {
		'allDatabases' : {
			'phpVersions': [
				'7.2',
			]
		},
		'reducedDatabases' : {
			'phpVersions': [
				'7.3',
				'7.4',
			],
			'databases': [
				'mysql:5.5',
			],
			'coverage': False
		},
	},

	'phpintegration': {
		'allDatabases' : {
			'phpVersions': [
				'7.2',
			]
		},
		'reducedDatabases' : {
			'phpVersions': [
				'7.3',
				'7.4',
			],
			'databases': [
				'mysql:5.5',
			],
			'coverage': False
		},
	},

	'acceptance': {
		'cli': {
			'suites': [
				'cliDataExporter'
			],
			'databases': [
				'mariadb:10.2',
				'mysql:5.5',
				'mysql:5.7',
				'postgres:9.4',
				'oracle'
			],
		},
	}
}

def main(ctx):
	initial = initialPipelines(ctx)

	before = beforePipelines(ctx)
	dependsOn(initial, before)

	coverageTests = coveragePipelines(ctx)
	if (coverageTests == False):
		print('Errors detected in coveragePipelines. Review messages above.')
		return []

	dependsOn(before, coverageTests)

	stages = stagePipelines(ctx)
	if (stages == False):
		print('Errors detected in stagePipelines. Review messages above.')
		return []

	dependsOn(before, stages)

	afterCoverageTests = afterCoveragePipelines(ctx)
	dependsOn(coverageTests, afterCoverageTests)


	after = afterPipelines(ctx)
	dependsOn(afterCoverageTests + stages, after)

	return initial + before + coverageTests + afterCoverageTests + stages + after

def initialPipelines(ctx):
	return dependencies(ctx)

def beforePipelines(ctx):
	return codestyle() + changelog(ctx) + phpstan() + phan()

def coveragePipelines(ctx):
	# All pipelines that might have coverage or other test analysis reported
	jsPipelines = javascript(ctx)
	phpunitPipelines = phptests(ctx, 'phpunit')
	phpintegrationPipelines = phptests(ctx, 'phpintegration')
	if (jsPipelines == False) or (phpunitPipelines == False) or (phpintegrationPipelines == False):
		return False

	return jsPipelines + phpunitPipelines + phpintegrationPipelines

def stagePipelines(ctx):
	# Pipelines that do not produce coverage or other test analysis reports
	litmusPipelines = litmus()
	davPipelines = dav()
	acceptancePipelines = acceptance(ctx)
	if (litmusPipelines == False) or (davPipelines == False) or (acceptancePipelines == False):
		return False

	return litmusPipelines + davPipelines + acceptancePipelines

def afterCoveragePipelines(ctx):
	return [
		sonarAnalysis(ctx)
	]

def afterPipelines(ctx):
	return [
		notify()
	]

def dependencies(ctx):
	pipelines = []

	if 'dependencies' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2'],
	}

	if 'defaults' in config:
		if 'dependencies' in config['defaults']:
			for item in config['defaults']['dependencies']:
				default[item] = config['defaults']['dependencies'][item]

	dependenciesConfig = config['dependencies']

	if type(dependenciesConfig) == "bool":
		if dependenciesConfig:
			# the config has 'dependencies' true, so specify an empty dict that will get the defaults
			dependenciesConfig = {}
		else:
			return pipelines

	if len(dependenciesConfig) == 0:
		# 'dependencies' is an empty dict, so specify a single section that will get the defaults
		dependenciesConfig = {'doDefault': {}}

	for category, matrix in dependenciesConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		for phpVersion in params['phpVersions']:
			name = 'install-dependencies-php%s' % phpVersion

			result = {
				'kind': 'pipeline',
				'type': 'docker',
				'name': name,
				'workspace' : {
					'base': '/drone',
					'path': 'src'
				},
				'steps':
					cacheRestore() +
					composerInstall(phpVersion) +
					vendorbinCodestyle(phpVersion) +
					vendorbinCodesniffer(phpVersion) +
					vendorbinPhan(phpVersion) +
					vendorbinPhpstan(phpVersion) +
					vendorbinBehat() +
					yarnInstall(phpVersion) +
					cacheRebuildOnEventPush() +
					cacheFlushOnEventPush(),
				'depends_on': [],
				'trigger': {
					'ref': [
						'refs/pull/**',
						'refs/tags/**'
					]
				}
			}

			for branch in config['branches']:
				result['trigger']['ref'].append('refs/heads/%s' % branch)

			pipelines.append(result)

	return pipelines

def codestyle():
	pipelines = []

	if 'codestyle' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2'],
	}

	if 'defaults' in config:
		if 'codestyle' in config['defaults']:
			for item in config['defaults']['codestyle']:
				default[item] = config['defaults']['codestyle'][item]

	codestyleConfig = config['codestyle']

	if type(codestyleConfig) == "bool":
		if codestyleConfig:
			# the config has 'codestyle' true, so specify an empty dict that will get the defaults
			codestyleConfig = {}
		else:
			return pipelines

	if len(codestyleConfig) == 0:
		# 'codestyle' is an empty dict, so specify a single section that will get the defaults
		codestyleConfig = {'doDefault': {}}

	for category, matrix in codestyleConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		for phpVersion in params['phpVersions']:
			name = 'coding-standard-php%s' % phpVersion

			result = {
				'kind': 'pipeline',
				'type': 'docker',
				'name': name,
				'workspace' : {
					'base': '/var/www/owncloud',
					'path': 'server/apps/%s' % config['app']
				},
				'steps': [
					{
						'name': 'coding-standard',
						'image': 'owncloudci/php:%s' % phpVersion,
						'pull': 'always',
						'commands': [
							'make test-php-style'
						]
					}
				],
				'depends_on': [],
				'trigger': {
					'ref': [
						'refs/pull/**',
						'refs/tags/**'
					]
				}
			}

			for branch in config['branches']:
				result['trigger']['ref'].append('refs/heads/%s' % branch)

			pipelines.append(result)

	return pipelines

def jscodestyle():
	pipelines = []

	if 'jscodestyle' not in config:
		return pipelines

	if type(config['jscodestyle']) == "bool":
		if not config['jscodestyle']:
			return pipelines

	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'coding-standard-js',
		'workspace' : {
			'base': '/var/www/owncloud',
			'path': 'server/apps/%s' % config['app']
		},
		'steps': [
			{
				'name': 'coding-standard-js',
				'image': 'owncloudci/php:7.2',
				'pull': 'always',
				'commands': [
					'make test-js-style'
				]
			}
		],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/pull/**',
				'refs/tags/**'
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	pipelines.append(result)

	return pipelines

def changelog(ctx):
	repo_slug = ctx.build.source_repo if ctx.build.source_repo else ctx.repo.slug
	pipelines = []

	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'changelog',
		'clone': {
			'disable': True,
		},
		'steps':
			[
				{
					'name': 'clone',
					'image': 'plugins/git-action:1',
					'pull': 'always',
					'settings': {
						'actions': [
							'clone',
						],
						'remote': 'https://github.com/%s' % (repo_slug),
						'branch': ctx.build.source if ctx.build.event == 'pull_request' else 'master',
						'path': '/drone/src',
						'netrc_machine': 'github.com',
						'netrc_username': {
							'from_secret': 'github_username',
						},
						'netrc_password': {
							'from_secret': 'github_token',
						},
					},
				},
				{
					'name': 'generate',
					'image': 'toolhippie/calens:latest',
					'pull': 'always',
					'commands': [
						'calens >| CHANGELOG.md',
					],
				},
				{
					'name': 'diff',
					'image': 'owncloud/alpine:latest',
					'pull': 'always',
					'commands': [
						'git diff',
					],
				},
				{
					'name': 'output',
					'image': 'toolhippie/calens:latest',
					'pull': 'always',
					'commands': [
						'cat CHANGELOG.md',
					],
				},
				{
					'name': 'publish',
					'image': 'plugins/git-action:1',
					'pull': 'always',
					'settings': {
						'actions': [
							'commit',
							'push',
						],
						'message': 'Automated changelog update [skip ci]',
						'branch': 'master',
						'author_email': 'devops@owncloud.com',
						'author_name': 'ownClouders',
						'netrc_machine': 'github.com',
						'netrc_username': {
							'from_secret': 'github_username',
						},
						'netrc_password': {
							'from_secret': 'github_token',
						},
					},
					'when': {
						'ref': {
							'exclude': [
								'refs/pull/**',
							],
						},
					},
				},
			],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/heads/master',
				'refs/pull/**',
			],
		},
	}

	pipelines.append(result)

	return pipelines

def phpstan():
	pipelines = []

	if 'phpstan' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2'],
		'logLevel': '2',
		'extraApps': {},
	}

	if 'defaults' in config:
		if 'phpstan' in config['defaults']:
			for item in config['defaults']['phpstan']:
				default[item] = config['defaults']['phpstan'][item]

	phpstanConfig = config['phpstan']

	if type(phpstanConfig) == "bool":
		if phpstanConfig:
			# the config has 'phpstan' true, so specify an empty dict that will get the defaults
			phpstanConfig = {}
		else:
			return pipelines

	if len(phpstanConfig) == 0:
		# 'phpstan' is an empty dict, so specify a single section that will get the defaults
		phpstanConfig = {'doDefault': {}}

	for category, matrix in phpstanConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		for phpVersion in params['phpVersions']:
			name = 'phpstan-php%s' % phpVersion

			result = {
				'kind': 'pipeline',
				'type': 'docker',
				'name': name,
				'workspace' : {
					'base': '/var/www/owncloud',
					'path': 'server/apps/%s' % config['app']
				},
				'steps':
					installCore('daily-master-qa', 'sqlite', False) +
					installApp(phpVersion) +
					installExtraApps(phpVersion, params['extraApps']) +
					setupServerAndApp(phpVersion, params['logLevel']) +
				[
					{
						'name': 'phpstan',
						'image': 'owncloudci/php:%s' % phpVersion,
						'pull': 'always',
						'commands': [
							'make test-php-phpstan'
						]
					}
				],
				'depends_on': [],
				'trigger': {
					'ref': [
						'refs/pull/**',
						'refs/tags/**'
					]
				}
			}

			for branch in config['branches']:
				result['trigger']['ref'].append('refs/heads/%s' % branch)

			pipelines.append(result)

	return pipelines

def phan():
	pipelines = []

	if 'phan' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2', '7.3', '7.4'],
	}

	if 'defaults' in config:
		if 'phan' in config['defaults']:
			for item in config['defaults']['phan']:
				default[item] = config['defaults']['phan'][item]

	phanConfig = config['phan']

	if type(phanConfig) == "bool":
		if phanConfig:
			# the config has 'phan' true, so specify an empty dict that will get the defaults
			phanConfig = {}
		else:
			return pipelines

	if len(phanConfig) == 0:
		# 'phan' is an empty dict, so specify a single section that will get the defaults
		phanConfig = {'doDefault': {}}

	for category, matrix in phanConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		for phpVersion in params['phpVersions']:
			name = 'phan-php%s' % phpVersion

			result = {
				'kind': 'pipeline',
				'type': 'docker',
				'name': name,
				'workspace' : {
					'base': '/var/www/owncloud',
					'path': 'server/apps/%s' % config['app']
				},
				'steps':
					installCore('daily-master-qa', 'sqlite', False) +
				[
					{
						'name': 'phan',
						'image': 'owncloudci/php:%s' % phpVersion,
						'pull': 'always',
						'commands': [
							'make test-php-phan'
						]
					}
				],
				'depends_on': [],
				'trigger': {
					'ref': [
						'refs/pull/**',
						'refs/tags/**'
					]
				}
			}

			for branch in config['branches']:
				result['trigger']['ref'].append('refs/heads/%s' % branch)

			pipelines.append(result)

	return pipelines

def litmus():
	pipelines = []

	if 'litmus' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2', '7.3', '7.4'],
		'logLevel': '2',
		'useHttps': True,
	}

	if 'defaults' in config:
		if 'litmus' in config['defaults']:
			for item in config['defaults']['litmus']:
				default[item] = config['defaults']['litmus'][item]

	litmusConfig = config['litmus']

	if type(litmusConfig) == "bool":
		if litmusConfig:
			# the config has 'litmus' true, so specify an empty dict that will get the defaults
			litmusConfig = {}
		else:
			return pipelines

	if len(litmusConfig) == 0:
		# 'litmus' is an empty dict, so specify a single section that will get the defaults
		litmusConfig = {'doDefault': {}}

	for category, matrix in litmusConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		for phpVersion in params['phpVersions']:
			name = 'litmus-php%s' % phpVersion
			db = 'mariadb:10.2'
			image = 'owncloud/litmus:latest'
			environment = {
				'LITMUS_PASSWORD': 'admin',
				'LITMUS_USERNAME': 'admin',
				'TESTS': 'basic copymove props locks http',
			}
			litmusCommand = '/usr/local/bin/litmus-wrapper'

			result = {
				'kind': 'pipeline',
				'type': 'docker',
				'name': name,
				'workspace' : {
					'base': '/drone',
					'path': 'src'
				},
				'steps':
					cacheRestore() +
					composerInstall(phpVersion) +
					yarnInstall(phpVersion) +
					installServer(phpVersion, db, params['logLevel'], params['useHttps']) +
					setupLocalStorage(phpVersion) +
					fixPermissions(phpVersion, False) +
					createShare(phpVersion) +
					owncloudLog('server', 'src') +
					[
						{
							'name': 'old-endpoint',
							'image': image,
							'pull': 'always',
							'environment': environment,
							'commands': [
								'source .env',
								'export LITMUS_URL="https://server/remote.php/webdav"',
								litmusCommand,
							]
						},
						{
							'name': 'new-endpoint',
							'image': image,
							'pull': 'always',
							'environment': environment,
							'commands': [
								'source .env',
								'export LITMUS_URL="https://server/remote.php/dav/files/admin"',
								litmusCommand,
							]
						},
						{
							'name': 'new-mount',
							'image': image,
							'pull': 'always',
							'environment': environment,
							'commands': [
								'source .env',
								'export LITMUS_URL="https://server/remote.php/dav/files/admin/local_storage/"',
								litmusCommand,
							]
						},
						{
							'name': 'old-mount',
							'image': image,
							'pull': 'always',
							'environment': environment,
							'commands': [
								'source .env',
								'export LITMUS_URL="https://server/remote.php/webdav/local_storage/"',
								litmusCommand,
							]
						},
						{
							'name': 'new-shared',
							'image': image,
							'pull': 'always',
							'environment': environment,
							'commands': [
								'source .env',
								'export LITMUS_URL="https://server/remote.php/dav/files/admin/new_folder/"',
								litmusCommand,
							]
						},
						{
							'name': 'old-shared',
							'image': image,
							'pull': 'always',
							'environment': environment,
							'commands': [
								'source .env',
								'export LITMUS_URL="https://server/remote.php/webdav/new_folder/"',
								litmusCommand,
							]
						},
						{
							'name': 'public-share',
							'image': image,
							'pull': 'always',
							'environment': {
								'LITMUS_PASSWORD': 'admin',
								'LITMUS_USERNAME': 'admin',
								'TESTS': 'basic copymove http',
							},
							'commands': [
								'source .env',
								'export LITMUS_URL=\'https://server/remote.php/dav/public-files/\'$PUBLIC_TOKEN',
								litmusCommand,
							]
						},
					],
				'services':
					databaseService(db) +
					owncloudService(phpVersion, 'server', '/drone/src', params['useHttps']),
				'depends_on': [],
				'trigger': {
					'ref': [
						'refs/pull/**',
						'refs/tags/**'
					]
				}
			}

			pipelines.append(result)

	return pipelines

def dav():
	pipelines = []

	if 'dav' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2', '7.3', '7.4'],
		'logLevel': '2'
	}

	if 'defaults' in config:
		if 'dav' in config['defaults']:
			for item in config['defaults']['dav']:
				default[item] = config['defaults']['dav'][item]

	davConfig = config['dav']

	if type(davConfig) == "bool":
		if davConfig:
			# the config has 'dav' true, so specify an empty dict that will get the defaults
			davConfig = {}
		else:
			return pipelines

	if len(davConfig) == 0:
		# 'dav' is an empty dict, so specify a single section that will get the defaults
		davConfig = {'doDefault': {}}

	for category, matrix in davConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		for phpVersion in params['phpVersions']:
			for davType in ['caldav-new', 'caldav-old', 'carddav-new', 'carddav-old']:
				name = '%s-php%s' % (davType, phpVersion)
				db = 'mariadb:10.2'

				if (davType == 'caldav-new'):
					scriptPath = 'apps/dav/tests/ci/caldav'

				if (davType == 'caldav-old'):
					scriptPath = 'apps/dav/tests/ci/caldav-old-endpoint'

				if (davType == 'carddav-new'):
					scriptPath = 'apps/dav/tests/ci/carddav'

				if (davType == 'carddav-old'):
					scriptPath = 'apps/dav/tests/ci/carddav-old-endpoint'

				result = {
					'kind': 'pipeline',
					'type': 'docker',
					'name': name,
					'workspace' : {
						'base': '/drone',
						'path': 'src'
					},
					'steps':
						cacheRestore() +
						composerInstall(phpVersion) +
						yarnInstall(phpVersion) +
						installServer(phpVersion, db, params['logLevel']) +
						davInstall(phpVersion, scriptPath) +
						fixPermissions(phpVersion, False) +
						owncloudLog('server', 'src') +
						[
							{
								'name': 'dav-test',
								'image': 'owncloudci/php:%s' % phpVersion,
								'pull': 'always',
								'commands': [
									'bash %s/script.sh' % scriptPath,
								]
							},
						],
					'services':
						databaseService(db),
					'depends_on': [],
					'trigger': {
						'ref': [
							'refs/pull/**',
							'refs/tags/**'
						]
					}
				}

				pipelines.append(result)

	return pipelines

def build():
	pipelines = []

	if 'build' not in config:
		return pipelines

	default = {
		'phpVersions': ['7.2'],
		'commands': [
			'make dist'
		],
		'extraEnvironment': {},
		'configureTarOnTag': False,
	}

	if 'defaults' in config:
		if 'build' in config['defaults']:
			for item in config['defaults']['build']:
				default[item] = config['defaults']['build'][item]

	matrix = config['build']

	if type(matrix) == "bool":
		if matrix:
			# the config has 'build' true, so specify an empty dict that will get the defaults
			matrix = {}
		else:
			return pipelines

	params = {}
	for item in default:
		params[item] = matrix[item] if item in matrix else default[item]

	for phpVersion in params['phpVersions']:
		result = {
			'kind': 'pipeline',
			'type': 'docker',
			'name': 'build',
			'workspace' : {
				'base': '/var/www/owncloud',
				'path': 'server/apps/%s' % config['app']
			},
			'steps': [
				{
					'name': 'build',
					'image': 'owncloudci/php:%s' % phpVersion,
					'pull': 'always',
					'environment': params['extraEnvironment'],
					'commands': params['commands']
				}
			] + ([
				{
					'name': 'github_release',
					'image': 'plugins/github-release',
					'pull': 'always',
					'settings': {
						'checksum': 'sha256',
						'file_exists': 'overwrite',
						'files': 'build/dist/%s.tar.gz' % config['app'],
						'prerelease': True,
					},
					'environment': {
						'GITHUB_TOKEN': {
							'from_secret': 'github_token'
						},
					},
					'when': {
						'event': [
							'tag'
						]
					},
				}
			] if params['configureTarOnTag'] else []),
			'depends_on': [],
			'trigger': {
				'ref': [
					'refs/pull/**',
					'refs/tags/**'
				]
			}
		}

		for branch in config['branches']:
			result['trigger']['ref'].append('refs/heads/%s' % branch)

		pipelines.append(result)

	return pipelines

def javascript(ctx):
	pipelines = []

	if 'javascript' not in config:
		return pipelines

	default = {
		'coverage': False,
		'logLevel': '2',
		'extraSetup': [],
		'extraServices': [],
		'extraEnvironment': {},
		'extraCommandsBeforeTestRun': [],
		'extraTeardown': [],
	}

	if 'defaults' in config:
		if 'javascript' in config['defaults']:
			for item in config['defaults']['javascript']:
				default[item] = config['defaults']['javascript'][item]

	matrix = config['javascript']

	if type(matrix) == "bool":
		if matrix:
			# the config has 'javascript' true, so specify an empty dict that will get the defaults
			matrix = {}
		else:
			return pipelines

	params = {}
	for item in default:
		params[item] = matrix[item] if item in matrix else default[item]

	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'javascript-tests',
		'workspace' : {
			'base': '/var/www/owncloud',
			'path': 'server/apps/%s' % config['app']
		},
		'steps':
			installCore('daily-master-qa', 'sqlite', False) +
			installApp('7.2') +
			setupServerAndApp('7.2', params['logLevel']) +
			params['extraSetup'] +
		[
			{
				'name': 'js-tests',
				'image': 'owncloudci/php:7.2',
				'pull': 'always',
				'environment': params['extraEnvironment'],
				'commands': params['extraCommandsBeforeTestRun'] + [
					'make test-js'
				]
			}
		] + params['extraTeardown'],
		'services': params['extraServices'],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/pull/**',
				'refs/tags/**'
			]
		}
	}

	if params['coverage']:
		result['steps'].append(
		{
			'name': 'coverage-cache',
			'image': 'plugins/s3',
			'pull': 'always',
			'settings': {
				'endpoint': {
                	'from_secret': 'cache_s3_endpoint'
             	},
              	'bucket': 'cache',
                'source': 'tests/output/coverage/PhantomJS 2.1.1 (Linux 0.0.0)/lcov.info',
                'target': '%s/%s/coverage' % (ctx.repo.slug, ctx.build.commit + '-${DRONE_BUILD_NUMBER}'),
                'path_style': True,
                'strip_prefix': 'tests/output/coverage/PhantomJS 2.1.1 (Linux 0.0.0)',
                'access_key': {
                	'from_secret': 'cache_s3_access_key'
                },
                'secret_key': {
                    'from_secret': 'cache_s3_secret_key'
             	}
			}
		})

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	return [result]

def phptests(ctx, testType):
	pipelines = []

	if testType not in config:
		return pipelines

	errorFound = False

	default = {
		'phpVersions': ['7.2', '7.3', '7.4'],
		'databases': [
			'sqlite', 'mariadb:10.2', 'mysql:5.5', 'mysql:5.7', 'postgres:9.4', 'oracle'
		],
		'coverage': True,
		'includeKeyInMatrixName': False,
		'logLevel': '2',
		'cephS3': False,
		'scalityS3': False,
		'externalTypes': ['none'],
		'extraSetup': [],
		'extraServices': [],
		'extraEnvironment': {},
		'extraCommandsBeforeTestRun': [],
		'extraApps': {},
		'extraTeardown': [],
	}

	if 'defaults' in config:
		if testType in config['defaults']:
			for item in config['defaults'][testType]:
				default[item] = config['defaults'][testType][item]

	phptestConfig = config[testType]

	if type(phptestConfig) == "bool":
		if phptestConfig:
			# the config has just True, so specify an empty dict that will get the defaults
			phptestConfig = {}
		else:
			return pipelines

	if len(phptestConfig) == 0:
		# the PHP test config is an empty dict, so specify a single section that will get the defaults
		phptestConfig = {'doDefault': {}}

	for category, matrix in phptestConfig.items():
		params = {}
		for item in default:
			params[item] = matrix[item] if item in matrix else default[item]

		cephS3Params = params['cephS3']
		if type(cephS3Params) == "bool":
			cephS3Needed = cephS3Params
			filesPrimaryS3NeededForCeph = cephS3Params
		else:
			cephS3Needed = True
			filesPrimaryS3NeededForCeph = cephS3Params['filesPrimaryS3Needed'] if 'filesPrimaryS3Needed' in cephS3Params else True

		scalityS3Params = params['scalityS3']
		if type(scalityS3Params) == "bool":
			scalityS3Needed = scalityS3Params
			filesPrimaryS3NeededForScality = scalityS3Params
		else:
			scalityS3Needed = True
			filesPrimaryS3NeededForScality = scalityS3Params['filesPrimaryS3Needed'] if 'filesPrimaryS3Needed' in scalityS3Params else True

		if ((config['app'] != 'files_primary_s3') and (filesPrimaryS3NeededForCeph or filesPrimaryS3NeededForScality)):
			# If we are not already 'files_primary_s3' and we need S3 storage, then install the 'files_primary_s3' app
			extraAppsDict  = {
				'files_primary_s3': 'composer install'
			}
			for app, command in params['extraApps'].items():
				extraAppsDict[app] = command
			params['extraApps'] = extraAppsDict

		for phpVersion in params['phpVersions']:

			if testType == 'phpunit':
				if params['coverage']:
					command = 'make test-php-unit-dbg'
				else:
					command = 'make test-php-unit'
			else:
				if params['coverage']:
					command = 'make test-php-integration-dbg'
				else:
					command = 'make test-php-integration'

			for db in params['databases']:
				for externalType in params['externalTypes']:
					keyString = '-' + category if params['includeKeyInMatrixName'] else ''
					filesExternalType = externalType if externalType != 'none' else ''
					name = '%s%s-php%s-%s' % (testType, keyString, phpVersion, db.replace(":", ""))
					maxLength = 50
					nameLength = len(name)
					if nameLength > maxLength:
						print("Error: generated phpunit stage name of length", nameLength, "is not supported. The maximum length is " + str(maxLength) + ".", name)
						errorFound = True

					if (filesExternalType == ''):
						# for the regular unit test runs, the clover coverage results are in a file named like:
						# autotest-clover-sqlite.xml
						coverageFileNameStart = 'autotest'
						extraCoverageRenameCommand = []
						extraCoverage = False
					else:
						# for the files-external unit test runs, the clover coverage results are in 2 files named like:
						# autotest-external-clover-sqlite.xml
						# autotest-external-clover-sqlite-samba.xml
						coverageFileNameStart = 'autotest-external'
						extraCoverageRenameCommand = [
							'mv tests/output/coverage/%s-clover-%s-%s.xml tests/output/coverage/clover-%s-%s.xml' % (coverageFileNameStart, getDbName(db), externalType, name, externalType)
						]
						extraCoverage = True

					result = {
						'kind': 'pipeline',
                        'type': 'docker',
                        'name': name,
                        'workspace' : {
                            'base': '/var/www/owncloud',
                            'path': 'server/apps/%s' % config['app']
                        },
                        'steps':
                            installCore('daily-master-qa', db, False) +
                            installApp(phpVersion) +
                            installExtraApps(phpVersion, params['extraApps']) +
                            setupServerAndApp(phpVersion, params['logLevel']) +
                            setupCeph(params['cephS3']) +
                            setupScality(params['scalityS3']) +
                            params['extraSetup'] +
                        [
                            {
                                'name': '%s-tests' % testType,
                                'image': 'owncloudci/php:%s' % phpVersion,
                                'pull': 'always',
                                'environment': params['extraEnvironment'],
                                'commands': params['extraCommandsBeforeTestRun'] + [
                                    command
                                ]
                            }
                        ] + params['extraTeardown'],
                        'services':
                            databaseService(db) +
                            cephService(params['cephS3']) +
                            scalityService(params['scalityS3']) +
                            params['extraServices'],
                        'depends_on': [],
                        'trigger': {
                            'ref': [
                                'refs/pull/**',
                                'refs/tags/**'
                            ]
                        }
                    }

					if params['coverage']:
						result['steps'].append({
							'name': 'coverage-rename',
							'image': 'owncloudci/php:%s' % phpVersion,
							'pull': 'always',
							'commands': [
								'mv tests/output/coverage/%s-clover-%s.xml tests/output/coverage/clover-%s.xml' % (coverageFileNameStart, getDbName(db), name)
							] + extraCoverageRenameCommand
						})
						result['steps'].append({
							'name': 'coverage-cache-1',
							'image': 'plugins/s3',
							'pull': 'always',
							'settings': {
								'endpoint': {
									'from_secret': 'cache_s3_endpoint'
								},
								'bucket': 'cache',
								'source': 'tests/output/coverage/clover-%s.xml'  % (name),
								'target': '%s/%s/coverage' % (ctx.repo.slug, ctx.build.commit + '-${DRONE_BUILD_NUMBER}'),
								'path_style': True,
								'strip_prefix': 'tests/output/coverage',
								'access_key': {
									'from_secret': 'cache_s3_access_key'
								},
								'secret_key': {
									'from_secret': 'cache_s3_secret_key'
								}
							}
						})
						if extraCoverage:
							result['steps'].append({
								'name': 'coverage-cache-2',
								'image': 'plugins/s3',
								'pull': 'always',
								'settings': {
									'endpoint': {
										'from_secret': 'cache_s3_endpoint'
									},
									'bucket': 'cache',
									'source': 'tests/output/coverage/clover-%s-%s.xml'  % (name, externalType),
									'target': '%s/%s/coverage' % (ctx.repo.slug, ctx.build.commit + '-${DRONE_BUILD_NUMBER}'),
									'path_style': True,
									'strip_prefix': 'tests/output/coverage',
									'access_key': {
										'from_secret': 'cache_s3_access_key'
									},
									'secret_key': {
										'from_secret': 'cache_s3_secret_key'
									}
								}
							})

					for branch in config['branches']:
						result['trigger']['ref'].append('refs/heads/%s' % branch)

					pipelines.append(result)

	if errorFound:
		return False

	return pipelines

def acceptance(ctx):
	pipelines = []

	if 'acceptance' not in config:
		return pipelines

	if type(config['acceptance']) == "bool":
		if not config['acceptance']:
			return pipelines

	errorFound = False

	default = {
		'servers': ['daily-master-qa', 'latest'],
		'browsers': ['chrome'],
		'phpVersions': ['7.2'],
		'databases': ['mariadb:10.2'],
		'federatedServerNeeded': False,
		'filterTags': '',
		'logLevel': '2',
		'emailNeeded': False,
		'ldapNeeded': False,
		'cephS3': False,
		'scalityS3': False,
		'ssl': False,
		'xForwardedFor': False,
		'extraSetup': [],
		'extraServices': [],
		'extraTeardown': [],
		'extraEnvironment': {},
		'extraCommandsBeforeTestRun': [],
		'extraApps': {},
		'useBundledApp': False,
		'includeKeyInMatrixName': False,
		'runAllSuites': False,
		'runCoreTests': False,
		'numberOfParts': 1,
		'cron': '',
	}

	if 'defaults' in config:
		if 'acceptance' in config['defaults']:
			for item in config['defaults']['acceptance']:
				default[item] = config['defaults']['acceptance'][item]

	for category, matrix in config['acceptance'].items():
		if type(matrix['suites']) == "list":
			suites = {}
			for suite in matrix['suites']:
				suites[suite] = suite
		else:
			suites = matrix['suites']

		for suite, alternateSuiteName in suites.items():
			isWebUI = suite.startswith('webUI')
			isAPI = suite.startswith('api')
			isCLI = suite.startswith('cli')

			params = {}
			for item in default:
				params[item] = matrix[item] if item in matrix else default[item]

			if isAPI or isCLI:
				params['browsers'] = ['']

			cephS3Params = params['cephS3']
			if type(cephS3Params) == "bool":
				cephS3Needed = cephS3Params
				filesPrimaryS3NeededForCeph = cephS3Params
			else:
				cephS3Needed = True
				filesPrimaryS3NeededForCeph = cephS3Params['filesPrimaryS3Needed'] if 'filesPrimaryS3Needed' in cephS3Params else True

			scalityS3Params = params['scalityS3']
			if type(scalityS3Params) == "bool":
				scalityS3Needed = scalityS3Params
				filesPrimaryS3NeededForScality = scalityS3Params
			else:
				scalityS3Needed = True
				filesPrimaryS3NeededForScality = scalityS3Params['filesPrimaryS3Needed'] if 'filesPrimaryS3Needed' in scalityS3Params else True

			if ((config['app'] != 'files_primary_s3') and (filesPrimaryS3NeededForCeph or filesPrimaryS3NeededForScality)):
				# If we are not already 'files_primary_s3' and we need S3 object storage, then install the 'files_primary_s3' app
				extraAppsDict  = {
					'files_primary_s3': 'composer install'
				}
				for app, command in params['extraApps'].items():
					extraAppsDict[app] = command
				params['extraApps'] = extraAppsDict

			for server in params['servers']:
				for browser in params['browsers']:
					for phpVersion in params['phpVersions']:
						for db in params['databases']:
							for runPart in range(1, params['numberOfParts'] + 1):
								name = 'unknown'

								if isWebUI or isAPI or isCLI:
									browserString = '' if browser == '' else '-' + browser
									keyString = '-' + category if params['includeKeyInMatrixName'] else ''
									partString = '' if params['numberOfParts'] == 1 else '-%d-%d' % (params['numberOfParts'], runPart)
									name = '%s%s%s-%s%s-%s-php%s' % (alternateSuiteName, keyString, partString, server.replace('daily-', '').replace('-qa', ''), browserString, db.replace(':', ''), phpVersion)
									maxLength = 50
									nameLength = len(name)
									if nameLength > maxLength:
										print("Error: generated stage name of length", nameLength, "is not supported. The maximum length is " + str(maxLength) + ".", name)
										errorFound = True

								environment = {}
								for env in params['extraEnvironment']:
									environment[env] = params['extraEnvironment'][env]

								environment['TEST_SERVER_URL'] = 'http://server'
								environment['BEHAT_FILTER_TAGS'] = params['filterTags']

								if (params['runAllSuites'] == False):
									environment['BEHAT_SUITE'] = suite
								else:
									environment['DIVIDE_INTO_NUM_PARTS'] = params['numberOfParts']
									environment['RUN_PART'] = runPart

								if isWebUI:
									environment['SELENIUM_HOST'] = 'selenium'
									environment['SELENIUM_PORT'] = '4444'
									environment['BROWSER'] = browser
									environment['PLATFORM'] = 'Linux'
									if (params['runCoreTests']):
										makeParameter = 'test-acceptance-core-webui'
									else:
										makeParameter = 'test-acceptance-webui'

								if isAPI:
									if (params['runCoreTests']):
										makeParameter = 'test-acceptance-core-api'
									else:
										makeParameter = 'test-acceptance-api'

								if isCLI:
									if (params['runCoreTests']):
										makeParameter = 'test-acceptance-core-cli'
									else:
										makeParameter = 'test-acceptance-cli'

								if params['emailNeeded']:
									environment['MAILHOG_HOST'] = 'email'

								if params['ldapNeeded']:
									environment['TEST_EXTERNAL_USER_BACKENDS'] = True

								if (cephS3Needed or scalityS3Needed):
									environment['OC_TEST_ON_OBJECTSTORE'] = '1'
									if (params['cephS3'] != False):
										environment['S3_TYPE'] = 'ceph'
									if (params['scalityS3'] != False):
										environment['S3_TYPE'] = 'scality'
								federationDbSuffix = '-federated'

								result = {
									'kind': 'pipeline',
									'type': 'docker',
									'name': name,
									'workspace' : {
										'base': '/var/www/owncloud',
										'path': 'testrunner/apps/%s' % config['app']
									},
									'steps':
										installCore(server, db, params['useBundledApp']) +
										installTestrunner('7.4', params['useBundledApp']) +
										(installFederated(server, phpVersion, params['logLevel'], db, federationDbSuffix) + owncloudLog('federated') if params['federatedServerNeeded'] else []) +
										installApp(phpVersion) +
										installExtraApps(phpVersion, params['extraApps']) +
										setupServerAndApp(phpVersion, params['logLevel']) +
										owncloudLog('server') +
										setupCeph(params['cephS3']) +
										setupScality(params['scalityS3']) +
										params['extraSetup'] +
										fixPermissions(phpVersion, params['federatedServerNeeded']) +
									[
										({
											'name': 'acceptance-tests',
											'image': 'owncloudci/php:7.4',
											'pull': 'always',
											'environment': environment,
											'commands': params['extraCommandsBeforeTestRun'] + [
												'touch /var/www/owncloud/saved-settings.sh',
												'. /var/www/owncloud/saved-settings.sh',
												'make %s' % makeParameter
											]
										}),
									] + params['extraTeardown'],
									'services':
										databaseService(db) +
										browserService(browser) +
										emailService(params['emailNeeded']) +
										ldapService(params['ldapNeeded']) +
										cephService(params['cephS3']) +
										scalityService(params['scalityS3']) +
										params['extraServices'] +
										owncloudService(server, phpVersion, 'server', '/var/www/owncloud/server', params['ssl'], params['xForwardedFor']) +
										((
											owncloudService(server, phpVersion, 'federated', '/var/www/owncloud/federated', params['ssl'], params['xForwardedFor']) +
											databaseServiceForFederation(db, federationDbSuffix)
										) if params['federatedServerNeeded'] else [] ),
									'depends_on': [],
									'trigger': {}
								}

								if (params['cron'] == ''):
									result['trigger']['ref'] = [
										'refs/pull/**',
										'refs/tags/**'
									]
									for branch in config['branches']:
										result['trigger']['ref'].append('refs/heads/%s' % branch)
								else:
									result['trigger']['cron'] = params['cron']

								pipelines.append(result)

	if errorFound:
		return False

	return pipelines

def sonarAnalysis(ctx, phpVersion = '7.4'):
	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'sonar-analysis',
		'workspace' : {
			'base': '/drone',
			'path': 'src'
		},
		'steps':
			cacheRestore() +
			composerInstall(phpVersion) +
			yarnInstall(phpVersion) +
			installServer(phpVersion, 'sqlite') +
		[
			{
				'name': 'sync-from-cache',
				'image': 'minio/mc',
				'pull': 'always',
				'environment': {
					'MC_HOST_cache': {
						'from_secret': 'cache_s3_connection_url'
					},
				},
				'commands': [
					'mkdir -p results',
					'mc mirror cache/cache/%s/%s/coverage results/' % (ctx.repo.slug, ctx.build.commit + '-${DRONE_BUILD_NUMBER}'),
				]
			},
			{
				'name': 'setup-before-sonarcloud',
				'image': 'owncloudci/php:%s' % phpVersion,
				'pull': 'always',
				'commands': [
					'pwd',
					'ls -l',
					'ls -l results',
					'ls -l apps',
					'ls -l config',
					'cd apps',
					'git clone https://github.com/owncloud/files_primary_s3.git',
					'cd files_primary_s3',
					'composer install',
					'cd /drone/src'
				]
			},
			{
				'name': 'sonarcloud',
				'image': 'sonarsource/sonar-scanner-cli',
				'pull': 'always',
				'environment': {
					'SONAR_TOKEN': {
						'from_secret': 'sonar_token'
					},
					'SONAR_PULL_REQUEST_BASE': 'master' if ctx.build.event == 'pull_request' else None,
					'SONAR_PULL_REQUEST_BRANCH': ctx.build.source if ctx.build.event == 'pull_request' else None,
					'SONAR_PULL_REQUEST_KEY': ctx.build.ref.replace("refs/pull/", "").split("/")[0] if ctx.build.event == 'pull_request' else None,
					'SONAR_SCANNER_OPTS': '-Xdebug'
				},
				'when': {
					'instance': [
						'drone.owncloud.services',
						'drone.owncloud.com'
					],
				}
			}
		],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/pull/**',
				'refs/tags/**'
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	return result


def notify():
	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'chat-notifications',
		'clone': {
			'disable': True
		},
		'steps': [
			{
				'name': 'notify-rocketchat',
				'image': 'plugins/slack:1',
				'pull': 'always',
				'settings': {
					'webhook': {
						'from_secret': config['rocketchat']['from_secret']
					},
					'channel': config['rocketchat']['channel']
				}
			}
		],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/tags/**'
			],
			'status': [
				'success',
				'failure'
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	return result

def databaseService(db):
	dbName = getDbName(db)
	if (dbName == 'mariadb') or (dbName == 'mysql'):
		return [{
			'name': dbName,
			'image': db,
			'pull': 'always',
			'environment': {
				'MYSQL_USER': getDbUsername(db),
				'MYSQL_PASSWORD': getDbPassword(db),
				'MYSQL_DATABASE': getDbDatabase(db),
				'MYSQL_ROOT_PASSWORD': getDbRootPassword()
			}
		}]

	if dbName == 'postgres':
		return [{
			'name': dbName,
			'image': db,
			'pull': 'always',
			'environment': {
				'POSTGRES_USER': getDbUsername(db),
				'POSTGRES_PASSWORD': getDbPassword(db),
				'POSTGRES_DB': getDbDatabase(db)
			}
		}]

	if dbName == 'oracle':
		return [{
			'name': dbName,
			'image': 'owncloudci/oracle-xe:latest',
			'pull': 'always',
			'environment': {
				'ORACLE_USER': getDbUsername(db),
				'ORACLE_PASSWORD': getDbPassword(db),
				'ORACLE_DB': getDbDatabase(db),
				'ORACLE_DISABLE_ASYNCH_IO': 'true',
			}
		}]

	return []

def browserService(browser):
	if browser == 'chrome':
		return [{
			'name': 'selenium',
			'image': 'selenium/standalone-chrome-debug:3.141.59-oxygen',
			'pull': 'always',
			'environment': {
				'JAVA_OPTS': '-Dselenium.LOGGER.level=WARNING'
			}
		}]

	if browser == 'firefox':
		return [{
			'name': 'selenium',
			'image': 'selenium/standalone-firefox-debug:3.8.1',
			'pull': 'always',
			'environment': {
				'JAVA_OPTS': '-Dselenium.LOGGER.level=WARNING',
				'SE_OPTS': '-enablePassThrough false'
			}
		}]

	return []

def emailService(emailNeeded):
	if emailNeeded:
		return [{
			'name': 'email',
			'image': 'mailhog/mailhog',
			'pull': 'always',
		}]

	return []

def ldapService(ldapNeeded):
	if ldapNeeded:
		return [{
			'name': 'ldap',
			'image': 'osixia/openldap',
			'pull': 'always',
			'environment': {
				'LDAP_DOMAIN': 'owncloud.com',
				'LDAP_ORGANISATION': 'owncloud',
				'LDAP_ADMIN_PASSWORD': 'admin',
				'LDAP_TLS_VERIFY_CLIENT': 'never',
				'HOSTNAME': 'ldap',
			}
		}]

	return []

def scalityService(serviceParams):
	serviceEnvironment = {
		'HOST_NAME': 'scality'
	}

	if type(serviceParams) == "bool":
		if not serviceParams:
			return []
	else:
		if 'extraEnvironment' in serviceParams:
			for env in serviceParams['extraEnvironment']:
				serviceEnvironment[env] = serviceParams['extraEnvironment'][env]

	return [{
		'name': 'scality',
		'image': 'owncloudci/scality-s3server',
		'pull': 'always',
		'environment': serviceEnvironment
	}]

def cephService(serviceParams):
	serviceEnvironment = {
		'NETWORK_AUTO_DETECT': '4',
		'RGW_NAME': 'ceph',
		'CEPH_DEMO_UID': 'owncloud',
		'CEPH_DEMO_ACCESS_KEY': 'owncloud123456',
		'CEPH_DEMO_SECRET_KEY': 'secret123456',
	}

	if type(serviceParams) == "bool":
		if not serviceParams:
			return []
	else:
		if 'extraEnvironment' in serviceParams:
			for env in serviceParams['extraEnvironment']:
				serviceEnvironment[env] = serviceParams['extraEnvironment'][env]

	return [{
		'name': 'ceph',
		'image': 'owncloudci/ceph:tag-build-master-jewel-ubuntu-16.04',
		'pull': 'always',
		'environment': serviceEnvironment
	}]

def owncloudService(version, phpVersion, name = 'server', path = '/var/www/owncloud/server', ssl = True, xForwardedFor = False):
	if ssl:
		environment = {
			'APACHE_WEBROOT': path,
			'APACHE_CONFIG_TEMPLATE': 'ssl',
			'APACHE_SSL_CERT_CN': 'server',
			'APACHE_SSL_CERT': '/var/www/owncloud/%s.crt' % name,
			'APACHE_SSL_KEY': '/var/www/owncloud/%s.key' % name
		}
	else:
		environment = {
			'APACHE_WEBROOT': path
		}

	return [{
		'name': name,
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': environment,
		'commands': ([
			'a2enmod remoteip',
			'cd /etc/apache2',
			'echo "RemoteIPHeader X-Forwarded-For" >> apache2.conf',
			# This replaces the first occurrence of "%h with "%a in apache2.conf file telling Apache to log the client
			# IP as recorded by mod_remoteip (%a) rather than hostname (%h). For more info check this out:
			# https://www.digitalocean.com/community/questions/get-client-public-ip-on-apache-server-used-behind-load-balancer
			'sed -i \'0,/"%h/s//"%a/\' apache2.conf',
		] if xForwardedFor else []) + [
			'/usr/local/bin/apachectl -e debug -D FOREGROUND',
		]
	}]

def getDbName(db):
	return db.split(':')[0]

def getDbUsername(db):
	name = getDbName(db)

	# The Oracle image has the Db Username hardcoded
	if name == 'oracle':
		return 'autotest'

	return 'owncloud'

def getDbPassword(db):
	name = getDbName(db)

	# The Oracle image has the Db Password hardcoded
	if name == 'oracle':
		return 'owncloud'

	return 'owncloud'

def getDbRootPassword():
	return 'owncloud'

def getDbDatabase(db):
	name = getDbName(db)

	# The Oracle image has the Db Name hardcoded
	if name == 'oracle':
		return 'XE'

	return 'owncloud'

def cacheRestore():
	return [{
		'name': 'cache-restore',
		'image': 'plugins/s3-cache:1',
		'pull': 'always',
		'settings': {
			'access_key': {
				'from_secret': 'cache_s3_access_key'
			},
			'endpoint': {
				'from_secret': 'cache_s3_endpoint'
			},
			'restore': True,
			'secret_key': {
				'from_secret': 'cache_s3_secret_key'
			}
		},
		'when': {
			'instance': [
				'drone.owncloud.services',
				'drone.owncloud.com'
			],
		}
	}]

def cacheRebuildOnEventPush():
	return [{
		'name': 'cache-rebuild',
		'image': 'plugins/s3-cache:1',
		'pull': 'always',
		'settings': {
			'access_key': {
				'from_secret': 'cache_s3_access_key'
			},
			'endpoint': {
				'from_secret': 'cache_s3_endpoint'
			},
			'mount': [
				'.cache'
			],
			'rebuild': True,
			'secret_key': {
				'from_secret': 'cache_s3_secret_key'
			}
		},
		'when': {
			'event': [
				'push',
			],
			'instance': [
				'drone.owncloud.services',
				'drone.owncloud.com'
			],
		}
	}]

def cacheFlushOnEventPush():
	return [{
		'name': 'cache-flush',
		'image': 'plugins/s3-cache:1',
		'pull': 'always',
		'settings': {
			'access_key': {
				'from_secret': 'cache_s3_access_key'
			},
			'endpoint': {
				'from_secret': 'cache_s3_endpoint'
			},
			'flush': True,
			'flush_age': '14',
			'secret_key': {
				'from_secret': 'cache_s3_secret_key'
			}
		},
		'when': {
			'event': [
				'push',
			],
			'instance': [
				'drone.owncloud.services',
				'drone.owncloud.com'
			],
		}
	}]

def composerInstall(phpVersion):
	return [{
		'name': 'composer-install',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'COMPOSER_HOME': '/drone/src/.cache/composer'
		},
		'commands': [
			'make install-composer-deps'
		]
	}]

def vendorbinCodestyle(phpVersion):
    return [{
        'name': 'vendorbin-codestyle',
        'image': 'owncloudci/php:%s' % phpVersion,
        'pull': 'always',
        'environment': {
            'COMPOSER_HOME': '/drone/src/.cache/composer'
        },
        'commands': [
            'make vendor-bin-codestyle'
        ]
    }]

def vendorbinCodesniffer(phpVersion):
	return [{
		'name': 'vendorbin-codesniffer',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'COMPOSER_HOME': '/drone/src/.cache/composer'
		},
		'commands': [
			'make vendor-bin-codesniffer'
		]
	}]

def vendorbinPhan(phpVersion):
	return [{
		'name': 'vendorbin-phan',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'COMPOSER_HOME': '/drone/src/.cache/composer'
		},
		'commands': [
			'make vendor-bin-phan'
		]
	}]

def vendorbinPhpstan(phpVersion):
	return [{
		'name': 'vendorbin-phpstan',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'COMPOSER_HOME': '/drone/src/.cache/composer'
		},
		'commands': [
			'make vendor-bin-phpstan'
		]
	}]

def vendorbinBehat():
	return [{
		'name': 'vendorbin-behat',
		'image': 'owncloudci/php:7.4',
		'pull': 'always',
		'environment': {
			'COMPOSER_HOME': '/drone/src/.cache/composer'
		},
		'commands': [
			'make vendor-bin-behat'
		]
	}]

def yarnInstall(phpVersion):
	return [{
		'name': 'yarn-install',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'NPM_CONFIG_CACHE': '/drone/src/.cache/npm',
			'YARN_CACHE_FOLDER': '/drone/src/.cache/yarn',
			'bower_storage__packages': '/drone/src/.cache/bower',
		},
		'commands': [
			'make install-nodejs-deps'
		]
	}]

def davInstall(phpVersion, scriptPath):
	return [{
		'name': 'dav-install',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': [
			'bash %s/install.sh' % scriptPath
		]
	}]

def setupLocalStorage(phpVersion):
	return [{
		'name': 'setup-storage',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'OC_PASS': '123456',
		},
		'commands': [
			'mkdir -p /drone/src/work/local_storage',
			'php occ app:enable files_external',
			'php occ config:system:set files_external_allow_create_new_local --value=true',
			'php occ config:app:set core enable_external_storage --value=yes',
			'php occ files_external:create local_storage local null::null -c datadir=/drone/src/work/local_storage',
			'php occ user:add --password-from-env user1',
		]
	}]

def createShare(phpVersion):
	return [{
		'name': 'create-share',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': [
			'curl -k -s -u user1:123456 -X MKCOL "https://server/remote.php/webdav/new_folder"',
			'curl -k -s -u user1:123456 "https://server/ocs/v2.php/apps/files_sharing/api/v1/shares" --data "path=/new_folder&shareType=0&permissions=15&name=new_folder&shareWith=admin"',
			'echo -n "PUBLIC_TOKEN=" > .env',
			'curl -k -s -u user1:123456 "https://server/ocs/v2.php/apps/files_sharing/api/v1/shares" --data "path=/new_folder&shareType=3&permissions=15&name=new_folder" | grep token | cut -d">" -f2 | cut -d"<" -f1 >> .env',
		]
	}]

def installCore(version, db, useBundledApp):
	host = getDbName(db)
	dbType = host

	username = getDbUsername(db)
	password = getDbPassword(db)
	database = getDbDatabase(db)

	if host == 'mariadb':
		dbType = 'mysql'

	if host == 'postgres':
		dbType = 'pgsql'

	if host == 'oracle':
		dbType = 'oci'

	stepDefinition = {
		'name': 'install-core',
		'image': 'owncloudci/core',
		'pull': 'always',
		'settings': {
			'version': version,
			'core_path': '/var/www/owncloud/server',
			'db_type': dbType,
			'db_name': database,
			'db_host': host,
			'db_username': username,
			'db_password': password
		}
	}

	if not useBundledApp:
		stepDefinition['settings']['exclude'] = 'apps/%s' % config['app']

	return [stepDefinition]

def installTestrunner(phpVersion, useBundledApp):
	return [{
		'name': 'install-testrunner',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': [
			'mkdir /tmp/testrunner',
			'git clone -b master --depth=1 https://github.com/owncloud/core.git /tmp/testrunner',
			'rsync -aIX /tmp/testrunner /var/www/owncloud',
		] + ([
			'cp -r /var/www/owncloud/testrunner/apps/%s /var/www/owncloud/server/apps/' % config['app']
		] if not useBundledApp else [])
	}]

def installExtraApps(phpVersion, extraApps):
	commandArray = []
	for app, command in extraApps.items():
		commandArray.append('git clone https://github.com/owncloud/%s.git /var/www/owncloud/testrunner/apps/%s' % (app, app))
		commandArray.append('cp -r /var/www/owncloud/testrunner/apps/%s /var/www/owncloud/server/apps/' % app)
		if (command != ''):
			commandArray.append('cd /var/www/owncloud/server/apps/%s' % app)
			commandArray.append(command)
		commandArray.append('cd /var/www/owncloud/server')
		commandArray.append('php occ a:l')
		commandArray.append('php occ a:e %s' % app)
		commandArray.append('php occ a:l')

	if (commandArray == []):
		return []

	return [{
		'name': 'install-extra-apps',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': commandArray
	}]

def installApp(phpVersion):
	if 'appInstallCommand' not in config:
		return []

	return [{
		'name': 'install-app-%s' % config['app'],
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': [
			'cd /var/www/owncloud/server/apps/%s' % config['app'],
			config['appInstallCommand']
		]
	}]

def setupServerAndApp(phpVersion, logLevel):
	return [{
		'name': 'setup-server-%s' % config['app'],
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': [
			'cd /var/www/owncloud/server',
			'php occ a:l',
			'php occ a:e %s' % config['app'],
			'php occ a:e testing',
			'php occ a:l',
			'php occ config:system:set trusted_domains 1 --value=server',
			'php occ log:manage --level %s' % logLevel,
		]
	}]

def setupCeph(serviceParams):
	if type(serviceParams) == "bool":
		if serviceParams:
			# specify an empty dict that will get the defaults
			serviceParams = {}
		else:
			return []

	createFirstBucket = serviceParams['createFirstBucket'] if 'createFirstBucket' in serviceParams else True
	setupCommands = serviceParams['setupCommands'] if 'setupCommands' in serviceParams else [
		'wait-for-it -t 600 ceph:80',
		'cd /var/www/owncloud/server/apps/files_primary_s3',
		'cp tests/drone/ceph.config.php /var/www/owncloud/server/config',
		'cd /var/www/owncloud/server',
	]

	return [{
		'name': 'setup-ceph',
		'image': 'owncloudci/php:7.2',
		'pull': 'always',
		'commands': setupCommands + ([
			'./apps/files_primary_s3/tests/drone/create-bucket.sh',
		] if createFirstBucket else [])
	}]

def setupScality(serviceParams):
	if type(serviceParams) == "bool":
		if serviceParams:
			# specify an empty dict that will get the defaults
			serviceParams = {}
		else:
			return []

	specialConfig = '.' + serviceParams['config'] if 'config' in serviceParams else ''
	configFile = 'scality%s.config.php' % specialConfig
	createFirstBucket = serviceParams['createFirstBucket'] if 'createFirstBucket' in serviceParams else True
	createExtraBuckets = serviceParams['createExtraBuckets'] if 'createExtraBuckets' in serviceParams else False
	setupCommands = serviceParams['setupCommands'] if 'setupCommands' in serviceParams else [
		'wait-for-it -t 600 scality:8000',
		'cd /var/www/owncloud/server/apps/files_primary_s3',
		'cp tests/drone/%s /var/www/owncloud/server/config' % configFile,
		'cd /var/www/owncloud/server'
	]

	return [{
		'name': 'setup-scality',
		'image': 'owncloudci/php:7.2',
		'pull': 'always',
		'commands': setupCommands + ([
			'php occ s3:create-bucket owncloud --accept-warning'
		] if createFirstBucket else []) + ([
			'for I in $(seq 1 9); do php ./occ s3:create-bucket  owncloud$I --accept-warning; done',
		] if createExtraBuckets else [])
	}]

def fixPermissions(phpVersion, federatedServerNeeded):
	return [{
		'name': 'fix-permissions',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'commands': [
			'chown -R www-data /var/www/owncloud/server',
			'wait-for-it -t 600 server:80'
		] + ([
			'chown -R www-data /var/www/owncloud/federated',
			'wait-for-it -t 600 federated:80'
		] if federatedServerNeeded else [])
	}]

def owncloudLog(server):
	return [{
		'name': 'owncloud-log-%s' % server,
		'image': 'owncloud/ubuntu:18.04',
		'pull': 'always',
		'detach': True,
		'commands': [
			'tail -f /var/www/owncloud/%s/data/owncloud.log' % server
		]
	}]

def dependsOn(earlierStages, nextStages):
	for earlierStage in earlierStages:
		for nextStage in nextStages:
			nextStage['depends_on'].append(earlierStage['name'])

def installFederated(federatedServerVersion, phpVersion, logLevel, db, dbSuffix = '-federated'):
	host = getDbName(db)
	dbType = host

	username = getDbUsername(db)
	password = getDbPassword(db)
	database = getDbDatabase(db) + dbSuffix

	if host == 'mariadb':
		dbType = 'mysql'
	elif host == 'postgres':
		dbType = 'pgsql'
	elif host == 'oracle':
		dbType = 'oci'
	return [
		{
			'name': 'install-federated',
			'image': 'owncloudci/core',
			'pull': 'always',
			'settings': {
				'version': federatedServerVersion,
				'core_path': '/var/www/owncloud/federated',
				'db_type': 'mysql',
				'db_name': database,
				'db_host': host + dbSuffix,
				'db_username': username,
				'db_password': password
			},
		},
		{
			'name': 'configure-federation',
			'image': 'owncloudci/php:%s' % phpVersion,
			'pull': 'always',
			'commands': [
				'echo "export TEST_SERVER_FED_URL=http://federated" > /var/www/owncloud/saved-settings.sh',
				'cd /var/www/owncloud/federated',
				'php occ a:l',
				'php occ a:e testing',
				'php occ a:l',
				'php occ config:system:set trusted_domains 1 --value=federated',
				'php occ log:manage --level %s' % logLevel,
				'php occ config:list'
			]
		}
	]

def databaseServiceForFederation(db, suffix):
	dbName = getDbName(db)

	if dbName not in ['mariadb', 'mysql']:
		print('Not implemented federated database for ', dbName)
		return []

	return [{
		'name': dbName + suffix,
		'image': db,
		'pull': 'always',
		'environment': {
			'MYSQL_USER': getDbUsername(db),
			'MYSQL_PASSWORD': getDbPassword(db),
			'MYSQL_DATABASE': getDbDatabase(db) + suffix,
			'MYSQL_ROOT_PASSWORD': getDbRootPassword()
		}
	}]

def installServer(phpVersion, db, logLevel = '2', ssl = False, federatedServerNeeded = False, proxyNeeded = False):
	return [{
		'name': 'install-server',
		'image': 'owncloudci/php:%s' % phpVersion,
		'pull': 'always',
		'environment': {
			'DB_TYPE': getDbName(db),
			'DB_USERNAME': getDbUsername(db),
			'DB_PASSWORD': getDbPassword(db),
			'DB_NAME': getDbDatabase(db)
		},
		'commands': [
			'bash tests/drone/install-server.sh',
			'php occ a:l',
			'php occ config:system:set trusted_domains 1 --value=server',
		] + ([
			'php occ config:system:set trusted_domains 2 --value=federated'
		] if federatedServerNeeded else []) + [
		] + ([
			'php occ config:system:set trusted_domains 3 --value=proxy'
		] if proxyNeeded else []) + [
			'php occ log:manage --level %s' % logLevel,
			'php occ config:list',
		] + ([
			'php occ security:certificates:import /drone/server.crt',
		] if ssl else []) + ([
			'php occ security:certificates:import /drone/federated.crt',
		] if federatedServerNeeded and ssl else []) + [
			'php occ security:certificates',
		]
	}]
