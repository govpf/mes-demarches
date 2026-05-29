import { explorerPlugin } from '@graphiql/plugin-explorer';
import { createGraphiQLFetcher } from '@graphiql/toolkit';
import { GraphiQL } from 'graphiql';
import { createElement } from 'react';
import { createRoot } from 'react-dom/client';

import { csrfToken, getConfig } from '@utils';

import '@graphiql/plugin-explorer/style.css';
import 'graphiql/style.css';

// pf: GraphiQL v5 utilise Monaco Editor qui exige une configuration explicite
// des Web Workers. Sans ça, le playground charge mais les opérations multiples
// font crasher le DropdownMenu du bouton Play (cf. erreurs MonacoEnvironment.getWorker).
import EditorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker';
import JsonWorker from 'monaco-editor/esm/vs/language/json/json.worker?worker';
import GraphQLWorker from 'monaco-graphql/esm/graphql.worker?worker';

self.MonacoEnvironment = {
  getWorker(_workerId, label) {
    if (label === 'json') return new JsonWorker();
    if (label === 'graphql') return new GraphQLWorker();
    return new EditorWorker();
  }
};

const { defaultQuery, defaultVariables } = getConfig();
const fetcher = createGraphiQLFetcher({
  url: '/api/v2/graphql',
  headers: { 'x-csrf-token': csrfToken() ?? '' }
});

function GraphiQLWithExplorer() {
  const explorer = explorerPlugin({ showAttribution: false });
  return createElement(GraphiQL, {
    fetcher: fetcher,
    defaultEditorToolsVisibility: true,
    plugins: [explorer],
    initialQuery: defaultQuery,
    initialVariables: defaultVariables
  });
}

const element = document.getElementById('playground');
if (element) {
  const root = createRoot(element);
  root.render(createElement(GraphiQLWithExplorer));
}
