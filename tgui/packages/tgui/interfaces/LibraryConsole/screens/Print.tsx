import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import {
  Box,
  Button,
  Input,
  Section,
  Stack,
  Tabs,
} from 'tgui-core/components';
import { classes } from 'tgui-core/react';

import type { LibraryConsoleData } from '../types';

export function Print(props) {
  const { act, data } = useBackend<LibraryConsoleData>();
  const {
    bible_name,
    bible_sprite,
    can_print_wiki_paths,
    deity,
    posters = [],
    religion,
  } = data;

  const [selectedPoster, setSelectedPoster] = useState(posters[0] ?? '');
  const [textbookTitle, setTextbookTitle] = useState('');
  const [textbookSlug, setTextbookSlug] = useState('');
  const [textbookAuthor, setTextbookAuthor] = useState('Community');

  const setTitle = (value: string | undefined) =>
    setTextbookTitle(String(value ?? ''));
  const setSlug = (value: string | undefined) =>
    setTextbookSlug(String(value ?? ''));
  const setAuthor = (value: string | undefined) =>
    setTextbookAuthor(String(value ?? ''));

  const normalizedTitle = textbookTitle.trim();
  const normalizedSlug = textbookSlug.trim();
  const normalizedAuthor = textbookAuthor.trim();
  const canPrintTextbook =
    normalizedTitle.length > 0 && normalizedSlug.length > 0;

  return (
    <Stack vertical fill>
      <Stack.Item grow>
        <Stack fill>
          <Stack.Item width="50%">
            <Section fill scrollable>
              <Tabs vertical>
                {posters.map((poster) => {
                  const selected = selectedPoster === poster;

                  return (
                    <Tabs.Tab
                      className="candystripe"
                      selected={selected}
                      color={selected && 'good'}
                      key={poster}
                      onClick={() => setSelectedPoster(poster)}
                    >
                      {poster}
                    </Tabs.Tab>
                  );
                })}
              </Tabs>
            </Section>
          </Stack.Item>
          <Stack.Item>
            <Stack vertical height="100%">
              <Stack.Item
                textAlign="center"
                fontSize="25px"
                italic
                bold
                textColor="#0b94c4"
              >
                {bible_name}
              </Stack.Item>
              <Stack.Item textAlign="center" fontSize="22px" textColor="purple">
                In the Name of {deity}
              </Stack.Item>
              <Stack.Item textAlign="center" fontSize="22px" textColor="purple">
                For the Sake of {religion}
              </Stack.Item>
              <Stack.Item align="center">
                <Box className={classes(['bibles224x224', bible_sprite])} />
              </Stack.Item>
            </Stack>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Section title={can_print_wiki_paths ? 'Wiki Textbook' : 'UGC Textbook'}>
          <Stack vertical>
            <Stack.Item>
              <Stack align="center">
                <Stack.Item width="80px">Title</Stack.Item>
                <Stack.Item grow>
                  <Input
                    fluid
                    value={textbookTitle}
                    placeholder="Textbook title"
                    onChange={setTitle}
                  />
                </Stack.Item>
              </Stack>
            </Stack.Item>
            <Stack.Item>
              <Stack align="center">
                <Stack.Item width="80px">Author</Stack.Item>
                <Stack.Item grow>
                  <Input
                    fluid
                    value={textbookAuthor}
                    placeholder="Community"
                    onChange={setAuthor}
                  />
                </Stack.Item>
              </Stack>
            </Stack.Item>
            <Stack.Item>
              <Stack align="center">
                <Stack.Item width="80px">Wiki Page</Stack.Item>
                {!can_print_wiki_paths && (
                  <Stack.Item>
                    <Box as="span" opacity={0.7}>
                      ugc/
                    </Box>
                  </Stack.Item>
                )}
                <Stack.Item grow>
                  <Input
                    fluid
                    value={textbookSlug}
                    placeholder={
                      can_print_wiki_paths
                        ? 'Guide_to_chemistry or ugc/my-atmos-guide'
                        : 'my-atmos-guide'
                    }
                    onChange={setSlug}
                  />
                </Stack.Item>
              </Stack>
            </Stack.Item>
            <Stack.Item>
              <Stack>
                <Stack.Item grow>
                  <Button
                    fluid
                    icon="book"
                    disabled={!canPrintTextbook}
                    onClick={() =>
                      act('print_ugc_textbook', {
                        title: normalizedTitle,
                        page_slug: normalizedSlug,
                        author: normalizedAuthor || 'Community',
                      })
                    }
                  >
                    Print Textbook
                  </Button>
                </Stack.Item>
                <Stack.Item grow>
                  <Button
                    fluid
                    icon="upload"
                    disabled={!canPrintTextbook}
                    onClick={() =>
                      act('upload_ugc_textbook', {
                        title: normalizedTitle,
                        page_slug: normalizedSlug,
                        author: normalizedAuthor || 'Community',
                      })
                    }
                  >
                    Add to Archive
                  </Button>
                </Stack.Item>
              </Stack>
            </Stack.Item>
          </Stack>
        </Section>
      </Stack.Item>
      <Stack.Item>
        <Stack justify="space-between">
          <Stack.Item grow>
            <Button
              fluid
              icon="scroll"
              fontSize="30px"
              lineHeight={2}
              textAlign="center"
              onClick={() =>
                act('print_poster', {
                  poster_name: selectedPoster,
                })
              }
            >
              Poster
            </Button>
          </Stack.Item>
          <Stack.Item grow>
            <Button
              fluid
              icon="cross"
              fontSize="30px"
              lineHeight={2}
              textAlign="center"
              onClick={() => act('print_bible')}
            >
              Bible
            </Button>
          </Stack.Item>
        </Stack>
      </Stack.Item>
    </Stack>
  );
}
