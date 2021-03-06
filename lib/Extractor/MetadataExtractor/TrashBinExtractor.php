<?php
/**
 * @author Ilja Neumann <ineumann@owncloud.com>
 * @author Juan Pablo Villafáñez <jvillafanez@solidgeargroup.com>
 *
 * @copyright Copyright (c) 2018, ownCloud GmbH
 * @license GPL-2.0
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 */
namespace OCA\DataExporter\Extractor\MetadataExtractor;

use OC\User\NoUserException;
use OCA\DataExporter\Extractor\MetadataExtractor\TrashBinExtractor\GetLocationQuery;
use OCA\DataExporter\Model\File;
use OCA\DataExporter\Model\TrashBinFile;
use OCA\DataExporter\Utilities\Iterators\Nodes\RecursiveNodeIteratorFactory;
use OCA\DataExporter\Utilities\Path;
use OCA\DataExporter\Utilities\StreamHelper;
use OCP\Files\Node;

/**
 * Extracts trash-bin metadata contents
 *
 * @package OCA\DataExporter\Extractor\MetadataExtractor
 */
class TrashBinExtractor {
	const FILE_NAME = 'trashbin.jsonl';
	/** @var RecursiveNodeIteratorFactory  */
	private $iteratorFactory;
	/**
	 * @var StreamHelper
	 */
	private $streamHelper;
	/**
	 * @var resource
	 */
	private $streamFile;

	/**
	 * @var GetLocationQuery
	 */
	private $getLocationQuery;

	public function __construct(RecursiveNodeIteratorFactory $iteratorFactory, StreamHelper $streamHelper, GetLocationQuery $getLocationQuery) {
		$this->iteratorFactory = $iteratorFactory;
		$this->streamHelper = $streamHelper;
		$this->getLocationQuery = $getLocationQuery;
	}

	/**
	 * @param string $userId
	 * @param string $exportPath
	 *
	 * @return void
	 *
	 * @throws NoUserException
	 */
	public function extract($userId, $exportPath, $extractFileIds = false) {
		list($iterator, $baseFolder) = $this->iteratorFactory->getTrashBinRecursiveIterator($userId);
		$ignoredAttributes = ['id'];
		if ($extractFileIds === true) {
			$ignoredAttributes = [];
		}

		$filename = Path::join($exportPath, $this::FILE_NAME);
		$this->streamFile = $this->streamHelper->initStream($filename, 'ab', true);

		foreach ($iterator as $node) {
			$nodePath = $node->getPath();
			$relativePath = $baseFolder->getRelativePath($nodePath);

			$file = new TrashBinFile();

			$file->setPath($relativePath);
			$file->setETag($node->getEtag());
			$file->setMtime($node->getMTime());
			$file->setPermissions($node->getPermissions());
			$file->setId($node->getId());

			$originalName = $this->getOriginalName($node);
			$deletionTimestamp = $this->getDeleteTimestamp($node);
			$originalLocation = $this->getLocationQuery->execute($userId, $originalName, $deletionTimestamp);

			// Has entry in trashbin-table
			if ($originalLocation !== null) {
				$file->setOriginalLocation($originalLocation);
				$file->setDeletionTimestamp($deletionTimestamp);
				$file->setOriginalName($originalName);
			}

			if ($node->getType() === Node::TYPE_FILE) {
				$file->setType(File::TYPE_FILE);
			} else {
				$file->setType(File::TYPE_FOLDER);
			}

			$this->streamHelper->writelnToStream($this->streamFile, $file, $ignoredAttributes);
		}
		$this->streamHelper->closeStream($this->streamFile);
	}

	private function getDeleteTimestamp($node) {
		$path = $node->getPath();
		return (int)\ltrim(\pathinfo($path, PATHINFO_EXTENSION), 'd');
	}

	private function getOriginalName($node) {
		$path = $node->getPath();
		$pathParts = \pathinfo($path);
		return $pathParts['filename'];
	}
}
